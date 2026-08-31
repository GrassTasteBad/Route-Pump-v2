<?php

namespace App\Services;

use App\Models\FuelPrice;
use Carbon\Carbon;

class PriceValidator
{
    /**
     * Haversine distance in kilometers.
     */
    public function haversine(float $lat1, float $lon1, float $lat2, float $lon2): float
    {
        $earthRadius = 6371; // km
        $dLat = deg2rad($lat2 - $lat1);
        $dLon = deg2rad($lon2 - $lon1);
        $a = sin($dLat / 2) * sin($dLat / 2) +
             cos(deg2rad($lat1)) * cos(deg2rad($lat2)) *
             sin($dLon / 2) * sin($dLon / 2);
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
        return $earthRadius * $c;
    }

    /**
     * Ray-Casting Point-in-Polygon check.
     */
    public function isPointInPolygon(float $lat, float $lng, ?array $polygon): bool
    {
        if (empty($polygon)) {
            return false;
        }
        $inside = false;
        $numPoints = count($polygon);
        for ($i = 0, $j = $numPoints - 1; $i < $numPoints; $j = $i++) {
            $latI = (double) $polygon[$i][0];
            $lngI = (double) $polygon[$i][1];
            $latJ = (double) $polygon[$j][0];
            $lngJ = (double) $polygon[$j][1];

            $intersect = (($lngI > $lng) != ($lngJ > $lng))
                && ($lat < ($latJ - $latI) * ($lng - $lngI) / ($lngJ - $lngI) + $latI);
            if ($intersect) {
                $inside = !$inside;
            }
        }
        return $inside;
    }

    /**
     * Validates that the motorist is physically inside or close to the gas station.
     */
    public function verifyProximity(float $userLat, float $userLng, $station): bool
    {
        $distance = $this->haversine($userLat, $userLng, (double)$station->latitude, (double)$station->longitude);
        $insideGeofence = $this->isPointInPolygon($userLat, $userLng, $station->geofence_polygon);

        // Accept if within 15 meters (0.015 km) or inside the polygon geofence boundary
        return ($distance <= 0.015 || $insideGeofence);
    }

    /**
     * Evaluates a newly reported price against historical station records, verified merchant baselines,
     * and localized pricing distributions. If it deviates by more than 15%, it's flagged as an anomaly.
     */
    public function checkPriceAnomaly(string $stationId, string $fuelType, float $price, $reporter = null, bool $ocrVerified = false): array
    {
        if ($ocrVerified) {
            return ['is_anomaly' => false, 'percentage' => 0, 'description' => ''];
        }

        if ($reporter && $reporter->trust_score < 30) {
            return [
                'is_anomaly' => true,
                'percentage' => 0,
                'description' => 'Automated anomaly flag: Reporter trust score is low (current: ' . $reporter->trust_score . ').'
            ];
        }

        $baselinePrice = null;
        $source = 'market average';

        // 1. Try to find a merchant verified price at this station within last 7 days
        $merchantPrice = FuelPrice::where('station_id', $stationId)
            ->where('fuel_type', $fuelType)
            ->where('status', 'merchant_verified')
            ->where('created_at', '>=', Carbon::now()->subDays(7))
            ->orderBy('created_at', 'desc')
            ->value('price');

        if ($merchantPrice) {
            $baselinePrice = (double) $merchantPrice;
            $source = 'verified merchant baseline';
        } else {
            // 2. Try to get average of accepted (non-flagged) historical prices for this station in the last 30 days
            $historicalAvg = FuelPrice::where('station_id', $stationId)
                ->where('fuel_type', $fuelType)
                ->where('created_at', '>=', Carbon::now()->subDays(30))
                ->whereNotExists(function ($query) {
                    $query->selectRaw(1)
                        ->from('anomaly_logs')
                        ->whereColumn('anomaly_logs.price_id', 'fuel_prices.id')
                        ->whereIn('anomaly_logs.status', ['pending', 'dismissed']);
                })
                ->avg('price');

            if ($historicalAvg) {
                $baselinePrice = (double) $historicalAvg;
                $source = 'historical station average';
            } else {
                // 3. Fall back to regional market average for this fuel type in Davao City
                $marketAvg = FuelPrice::where('fuel_type', $fuelType)
                    ->whereNotExists(function ($query) {
                        $query->selectRaw(1)
                            ->from('anomaly_logs')
                            ->whereColumn('anomaly_logs.price_id', 'fuel_prices.id')
                            ->whereIn('anomaly_logs.status', ['pending', 'dismissed']);
                    })
                    ->avg('price');

                if ($marketAvg) {
                    $baselinePrice = (double) $marketAvg;
                }
            }
        }

        if (!$baselinePrice) {
            // Default regional market fallback baselines if database has no historical records yet
            $defaults = [
                'regular unleaded (91)' => 70.00,
                'premium unleaded(95)' => 76.00,
                'regular diesel'       => 71.00,
                'premium diesel'       => 77.00,
            ];
            $baselinePrice = $defaults[$fuelType] ?? 70.00;
            $source = 'regional market baseline';
        }

        $percentageDifference = abs(($price - $baselinePrice) / $baselinePrice) * 100;

        // Devise standard deviation outlier flag at > 15%
        if ($percentageDifference > 15.0) {
            $desc = sprintf(
                'Price of ₱%.2f for %s deviates by %.1f%% from %s (₱%.2f).',
                $price,
                ucfirst($fuelType),
                $percentageDifference,
                $source,
                $baselinePrice
            );
            return [
                'is_anomaly' => true,
                'percentage' => $percentageDifference,
                'description' => $desc,
            ];
        }

        return ['is_anomaly' => false, 'percentage' => $percentageDifference, 'description' => ''];
    }
}
