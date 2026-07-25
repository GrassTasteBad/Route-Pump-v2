<?php

namespace App\Services;

use App\Models\GasStation;
use App\Models\FuelPrice;
use Carbon\Carbon;

class RoutingEngine
{
    private QueueEstimator $queueEstimator;

    public function __construct(QueueEstimator $queueEstimator)
    {
        $this->queueEstimator = $queueEstimator;
    }

    /**
     * Haversine distance in kilometers.
     */
    private function haversine(float $lat1, float $lon1, float $lat2, float $lon2): float
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
     * Determines whether the current time is rush hour (7:30 - 9:00 AM, 5:00 - 6:30 PM).
     */
    public function isRushHour(): bool
    {
        $now = Carbon::now();
        $hour = $now->hour;
        $minute = $now->minute;
        $timeDecimal = $hour + ($minute / 60.0);

        return ($timeDecimal >= 7.5 && $timeDecimal <= 9.0) || ($timeDecimal >= 17.0 && $timeDecimal <= 18.5);
    }

    /**
     * Returns the traffic multiplier.
     */
    public function getTrafficFactor(): float
    {
        return $this->isRushHour() ? 1.8 : 1.2;
    }

    /**
     * Retrieves the latest price of a specific fuel type at a station.
     */
    private function getStationFuelPrice(string $stationId, string $fuelType): ?float
    {
        $latestPrice = FuelPrice::getLatestValidPrice($stationId, $fuelType);
        return $latestPrice ? (double) $latestPrice->price : null;
    }

    /**
     * Computes the Multi-Criteria Decision Making (MCDM) routing rankings based on relative net savings.
     */
    public function computeOptimalRoutes(
        float $lat,
        float $lng,
        string $fuelType,
        float $liters = 30.0,
        ?float $budget = null,
        string $purchaseMode = 'liters',
        float $efficiency = 12.5,
        float $idlingRate = 1.2,
        ?string $excludeUserId = null,
        ?string $preferredBrand = null,
        ?string $priceSensitivity = null
    ): array {
        $trafficFactor = $this->getTrafficFactor();
        $isRushHour = $this->isRushHour();
        $useBudgetMode = ($purchaseMode === 'budget' && $budget !== null && $budget > 0);

        // Fetch active stations
        $query = GasStation::where('status', 'active');
        if ($preferredBrand && strtolower($preferredBrand) !== 'all') {
            $query->where('name', 'like', '%' . $preferredBrand . '%');
        }
        $stations = $query->get();

        if ($stations->isEmpty()) {
            return [];
        }

        // 1. Gather distance data and find baseline (nearest) station
        $stationsData = [];
        $nearestStation = null;
        $minDistance = INF;

        foreach ($stations as $station) {
            $price = $this->getStationFuelPrice($station->id, $fuelType);
            if ($price === null) {
                continue;
            }

            $rawDist = $this->haversine($lat, $lng, (double) $station->latitude, (double) $station->longitude);

            if ($rawDist < $minDistance) {
                $minDistance = $rawDist;
                $nearestStation = [
                    'station' => $station,
                    'price' => $price,
                    'raw_distance' => $rawDist,
                ];
            }

            $stationsData[] = [
                'station' => $station,
                'price' => $price,
                'raw_distance' => $rawDist,
            ];
        }

        if (empty($stationsData) || !$nearestStation) {
            return [];
        }

        $baselinePrice = $nearestStation['price'];
        $baselineId = $nearestStation['station']->id;

        // 2. Pre-calculate travel cost for the baseline station to use in relative savings
        $baselineRawDist = $nearestStation['raw_distance'];
        $baselineStreetDist = $baselineRawDist * 1.3;
        $baselineEffectiveDist = $baselineStreetDist * $trafficFactor;
        $baselineQueue = $this->queueEstimator->calculateStationQueue($baselineId, $excludeUserId);
        $baselineIdleHours = $baselineQueue['wait_time_hours'];

        $baseFuelDriving = $baselineEffectiveDist / $efficiency;
        $baseFuelIdling = $baselineIdleHours * $idlingRate;
        $baseTotalFuel = $baseFuelDriving + $baseFuelIdling;
        $cTravelBaseline = $baseTotalFuel * $baselinePrice;

        // 3. Compute costs and relative net savings for all candidate stations
        $results = [];
        foreach ($stationsData as $item) {
            $station = $item['station'];
            $price = $item['price'];
            $rawDist = $item['raw_distance'];

            $streetDist = $rawDist * 1.3;
            $effectiveDist = $streetDist * $trafficFactor;

            $queueData = $this->queueEstimator->calculateStationQueue($station->id, $excludeUserId);
            $tIdleHours = $queueData['wait_time_hours'];

            $fuelBurnedDriving = $effectiveDist / $efficiency;
            $fuelBurnedIdling = $tIdleHours * $idlingRate;
            $totalFuelBurned = $fuelBurnedDriving + $fuelBurnedIdling;

            $cTravel = $totalFuelBurned * $price;

            if ($useBudgetMode) {
                $targetLiters = $budget / $price;
                $baselineLiters = $budget / $baselinePrice;
                $grossSavings = ($targetLiters - $baselineLiters) * $price;
                $displayLiters = $targetLiters;
            } else {
                $grossSavings = $liters * ($baselinePrice - $price);
                $displayLiters = $liters;
            }

            $sensitivityFactor = 1.0;
            if ($priceSensitivity) {
                $sens = strtolower($priceSensitivity);
                if ($sens === 'high') {
                    $sensitivityFactor = 0.5;
                } elseif ($sens === 'low') {
                    $sensitivityFactor = 2.0;
                }
            }

            // Relative net savings formula: S_net = Gross_Savings - (C_travel_target - C_travel_baseline) * PriceSensitivityFactor
            // For the baseline station itself, gross savings is 0, and relative cost is 0, so S_net is exactly 0.
            $netSavings = $grossSavings - ($cTravel - $cTravelBaseline) * $sensitivityFactor;

            $pathNodes = [
                ['name' => 'Start', 'lat' => $lat, 'lng' => $lng],
                ['name' => $station->name . ' - ' . $station->branch, 'lat' => (double)$station->latitude, 'lng' => (double)$station->longitude],
            ];

            // Load all fuel prices for the response
            $stationPrices = [];
            foreach (['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel'] as $type) {
                $stationPrices[$type] = $this->getStationFuelPrice($station->id, $type);
            }

            $results[] = [
                'station_id' => $station->id,
                'name' => $station->name,
                'branch' => $station->branch,
                'latitude' => (double)$station->latitude,
                'longitude' => (double)$station->longitude,
                'price' => $price,
                'prices' => $stationPrices,
                'raw_distance_km' => round($rawDist, 2),
                'effective_distance_km' => round($effectiveDist, 2),
                'queue_count' => $queueData['queue_count'],
                'wait_time_minutes' => round($queueData['wait_time_minutes'], 1),
                'fuel_burned_driving_liters' => round($fuelBurnedDriving, 2),
                'fuel_burned_idling_liters' => round($fuelBurnedIdling, 2),
                'travel_cost_php' => round($cTravel, 2),
                'gross_savings_php' => round($grossSavings, 2),
                'net_savings_php' => round($netSavings, 2),
                'liters_purchased' => round($displayLiters, 2),
                'path_nodes' => $pathNodes,
                'is_baseline' => ($station->id === $baselineId),
            ];
        }

        // Sort by Net Savings descending
        usort($results, function ($a, $b) {
            return $b['net_savings_php'] <=> $a['net_savings_php'];
        });

        return [
            'baseline_station_id' => $baselineId,
            'baseline_price' => $baselinePrice,
            'liters' => $liters,
            'fuel_efficiency_kml' => $efficiency,
            'traffic_factor' => $trafficFactor,
            'rush_hour' => $isRushHour,
            'stations' => $results,
        ];
    }
}
