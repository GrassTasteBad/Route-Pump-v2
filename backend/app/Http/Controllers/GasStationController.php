<?php

namespace App\Http\Controllers;

use App\Models\GasStation;
use App\Models\FuelPrice;
use App\Models\AnomalyLog;
use App\Services\QueueEstimator;
use App\Services\PriceValidator;
use App\Services\RoutingEngine;
use App\Services\OcrService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Storage;

class GasStationController extends Controller
{
    private QueueEstimator $queueEstimator;
    private PriceValidator $priceValidator;
    private RoutingEngine $routingEngine;
    private OcrService $ocrService;

    public function __construct(
        QueueEstimator $queueEstimator,
        PriceValidator $priceValidator,
        RoutingEngine $routingEngine,
        OcrService $ocrService
    ) {
        $this->queueEstimator = $queueEstimator;
        $this->priceValidator = $priceValidator;
        $this->routingEngine = $routingEngine;
        $this->ocrService = $ocrService;
    }

    private function validateDavaoCoordinates(float $lat, float $lng): bool
    {
        // Davao City geographical bounding box: Lat 6.8500 to 7.5500, Lng 125.2500 to 125.8500
        return ($lat >= 6.8500 && $lat <= 7.5500 && $lng >= 125.2500 && $lng <= 125.8500);
    }

    /**
     * Get latest prices for a station with credibility metrics.
     */
    private function getStationPrices(string $stationId): array
    {
        $prices = [];
        $credibility = [];
        foreach (['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel'] as $type) {
            $latestPrice = FuelPrice::getLatestValidPrice($stationId, $type);
            $prices[$type] = $latestPrice ? (double)$latestPrice->price : null;

            if ($latestPrice) {
                $confirmations = FuelPrice::where('station_id', $stationId)
                    ->where('fuel_type', $type)
                    ->where('price', $latestPrice->price)
                    ->count();

                $createdAt = \Carbon\Carbon::parse($latestPrice->created_at);
                $secondsAgo = $createdAt->diffInSeconds(\Carbon\Carbon::now());
                $freshness = 'stale';
                if ($secondsAgo < 3600) {
                    $freshness = 'fresh';
                } elseif ($secondsAgo < 43200) {
                    $freshness = 'recent';
                } elseif ($secondsAgo < 86400) {
                    $freshness = 'aging';
                }

                $credibility[$type] = [
                    'price'              => (double)$latestPrice->price,
                    'confirmation_count' => max(1, $confirmations),
                    'ocr_verified'       => (bool)$latestPrice->ocr_verified,
                    'merchant_verified'  => $latestPrice->status === 'merchant_verified',
                    'updated_at'         => $createdAt->toIso8601String(),
                    'time_decay_seconds' => $secondsAgo,
                    'freshness_status'   => $freshness,
                ];
            } else {
                $credibility[$type] = null;
            }
        }
        return ['prices' => $prices, 'credibility' => $credibility];
    }

    // GET /api/gas-stations
    public function index()
    {
        $excludeUserId = request()->user() ? request()->user()->id : null;
        $stations = GasStation::all()->map(function ($station) use ($excludeUserId) {
            $queueData = $this->queueEstimator->calculateStationQueue($station->id, $excludeUserId);
            $priceData = $this->getStationPrices($station->id);
            
            return [
                'id'                => $station->id,
                'name'              => $station->name,
                'branch'            => $station->branch,
                'latitude'          => (double)$station->latitude,
                'longitude'         => (double)$station->longitude,
                'geofence_polygon'  => $station->geofence_polygon,
                'status'            => $station->status,
                'fuel_availability' => $station->fuel_availability ?? [],
                'queue_count'       => $queueData['queue_count'],
                'wait_time_minutes' => $queueData['wait_time_minutes'],
                'prices'            => $priceData['prices'],
                'price_credibility' => $priceData['credibility'],
            ];
        });

        return response($stations, 200);
    }

    /**
     * Generate a fixed 15-meter radius circular geofence polygon (16 points).
     */
    private function generateFixedGeofence(float $lat, float $lng, int $radiusMeters = 15): array
    {
        $earthRadius = 6371000; // meters
        $points = [];
        $numPoints = 16;
        for ($i = 0; $i < $numPoints; $i++) {
            $angle = deg2rad(($i * 360) / $numPoints);
            $dLat = ($radiusMeters / $earthRadius) * cos($angle);
            $dLng = ($radiusMeters / ($earthRadius * cos(deg2rad($lat)))) * sin($angle);
            $points[] = [
                round($lat + rad2deg($dLat), 8),
                round($lng + rad2deg($dLng), 8),
            ];
        }
        return $points;
    }

    // POST /api/gas-stations (Admin only)
    public function store(Request $request)
    {
        $fields = $request->validate([
            'name' => 'required|string',
            'branch' => 'required|string',
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'status' => 'nullable|string|in:active,maintenance,out_of_stock,inactive,deactivated',
        ]);

        $geofencePolygon = $this->generateFixedGeofence(
            (double)$fields['latitude'],
            (double)$fields['longitude']
        );

        $station = GasStation::create([
            'id' => (string) Str::uuid(),
            'name' => $fields['name'],
            'branch' => $fields['branch'],
            'latitude' => $fields['latitude'],
            'longitude' => $fields['longitude'],
            'geofence_polygon' => $geofencePolygon,
            'status' => $fields['status'] ?? 'active',
        ]);

        return response($station, 201);
    }

    // DELETE /api/gas-stations/{id} (Admin only)
    public function destroy($id)
    {
        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Station not found'], 404);
        }
        $station->delete();
        return response(['message' => 'Station deleted successfully'], 200);
    }

    // POST /api/gas-stations/{id}/status (Partner or Admin)
    public function updateStatus(Request $request, $id)
    {
        $request->validate([
            'status' => 'required|string|in:active,maintenance,out_of_stock,inactive,deactivated',
        ]);

        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Station not found'], 404);
        }

        // Verify partner is linked to this station
        $user = $request->user();
        if ($user->role === 'partner' && $user->station_id !== $station->id) {
            return response(['message' => 'Unauthorized: You do not work at this branch.'], 403);
        }

        $station->status = $request->status;
        $station->save();

        return response($station, 200);
    }

    // POST /api/gas-stations/{id}/fuel-availability
    public function updateFuelAvailability(Request $request, $id)
    {
        $request->validate([
            'fuel_type' => 'required|string|in:regular unleaded (91),premium unleaded(95),regular diesel,premium diesel',
            'available'  => 'required|boolean',
        ]);

        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Station not found'], 404);
        }

        // Only the assigned partner or an admin may do this
        $user = $request->user();
        if ($user->role === 'partner' && $user->station_id !== $station->id) {
            return response(['message' => 'Unauthorized: You do not work at this branch.'], 403);
        }

        // Merge the updated flag into the existing JSON column
        $availability = $station->fuel_availability ?? [];
        $availability[$request->fuel_type] = (bool) $request->available;
        $station->fuel_availability = $availability;
        $station->save();

        return response([
            'message'           => 'Fuel availability updated.',
            'fuel_availability' => $station->fuel_availability,
        ], 200);
    }

    // POST /api/gas-stations/{id}/prices
    public function reportPrice(Request $request, $id)
    {
        $fields = $request->validate([
            'fuel_type' => 'required|string|in:regular unleaded (91),premium unleaded(95),regular diesel,premium diesel',
            'price' => 'required|numeric|min:1',
            'latitude' => 'nullable|numeric',
            'longitude' => 'nullable|numeric',
            'photo' => 'nullable|image|max:10240',
        ]);

        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Station not found'], 404);
        }

        $user = $request->user();

        // 1. Determine status
        $status = 'crowdsourced';
        if ($user->role === 'partner' && $user->station_id === $station->id) {
            $status = 'merchant_verified';
        }

        // 2. Geofence evaluation: Determine if submission is within geofence range (~150m or polygon)
        $isInsideGeofence = true;
        if (isset($fields['latitude']) && isset($fields['longitude'])) {
            $userLat = (float)$fields['latitude'];
            $userLng = (float)$fields['longitude'];
            $distance = $this->priceValidator->haversine($userLat, $userLng, (float)$station->latitude, (float)$station->longitude);
            $insidePolygon = $this->priceValidator->isPointInPolygon($userLat, $userLng, $station->geofence_polygon ?? []);
            $isInsideGeofence = ($distance <= 0.150 || $insidePolygon);
        }


        // 2.5 Real OCR verification (mobile runs ML Kit; backend validates the image is genuine)
        $ocrVerified = false;
        $imagePath = null;
        if ($request->hasFile('photo')) {
            $photo = $request->file('photo');
            $imagePath = $photo->store('proofs', 'public');
            // Pass the stored path and reported price — OcrService validates the image is real
            $extractedPrice = $this->ocrService->extractPrice($imagePath, (double)$fields['price']);
            if ($extractedPrice !== null) {
                $ocrVerified = true;
            }
        }

        // Check for exact duplicate submission by same user for same station & fuel type within 2 minutes
        $recentDuplicate = FuelPrice::where('station_id', $station->id)
            ->where('fuel_type', $fields['fuel_type'])
            ->where('reported_by', $user->id)
            ->where('price', $fields['price'])
            ->where('created_at', '>=', now()->subMinutes(2))
            ->first();

        if ($recentDuplicate) {
            return response([
                'message' => 'Price already recorded recently.',
                'price' => $recentDuplicate,
                'anomaly_flagged' => false,
                'is_inside_geofence' => $isInsideGeofence,
            ], 200);
        }

        // 3. Create price record
        $priceRecord = FuelPrice::create([
            'id' => (string) Str::uuid(),
            'station_id' => $station->id,
            'fuel_type' => $fields['fuel_type'],
            'price' => $fields['price'],
            'reported_by' => $user->id,
            'status' => $status,
            'created_at' => now(),
            'image_path' => $imagePath,
            'ocr_verified' => $ocrVerified,
            'is_inside_geofence' => $isInsideGeofence,
        ]);

        // 4. Anomaly detection (only for crowdsourced prices)
        if ($status === 'crowdsourced') {
            $anomalyResult = $this->priceValidator->checkPriceAnomaly(
                $station->id, 
                $fields['fuel_type'], 
                (double)$fields['price'], 
                $user, 
                $ocrVerified
            );
            
            if ($anomalyResult['is_anomaly']) {
                AnomalyLog::create([
                    'id' => (string) Str::uuid(),
                    'station_id' => $station->id,
                    'price_id' => $priceRecord->id,
                    'description' => $anomalyResult['description'],
                    'status' => 'pending',
                ]);

                return response([
                    'message' => 'Price submitted but flagged for moderation due to standard deviation anomaly.',
                    'price' => $priceRecord,
                    'anomaly_flagged' => true,
                ], 202);
            } else {
                // If not flagged and reporter is a motorist, increment trust score
                if ($user->role === 'motorist') {
                    $user->trust_score = min(100, $user->trust_score + 2);
                    $user->save();
                }
            }
        } else {
            // Partner/Merchant override: resolve any pending anomaly logs for this station and fuel type
            $pendingAnomalies = AnomalyLog::where('station_id', $station->id)
                ->where('status', 'pending')
                ->whereHas('price', function ($q) use ($fields) {
                    $q->where('fuel_type', $fields['fuel_type']);
                })->get();

            foreach ($pendingAnomalies as $anomaly) {
                $anomaly->status = 'resolved';
                $anomaly->save();
            }

            // Automatically invalidate/deactivate conflicting crowdsourced prices
            FuelPrice::where('station_id', $station->id)
                ->where('fuel_type', $fields['fuel_type'])
                ->where('status', 'crowdsourced')
                ->delete();
        }

        return response([
            'message' => $isInsideGeofence 
                ? 'Price updated successfully.' 
                : 'Recorded successfully. Waiting for other motorists to submit prices.',
            'price' => $priceRecord,
            'anomaly_flagged' => false,
            'is_inside_geofence' => $isInsideGeofence,
        ], 201);
    }

    // GET /api/gas-stations/routing (Net-Cost Pathfinding)
    public function routing(Request $request)
    {
        $fields = $request->validate([
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'fuel_type' => 'required|string|in:regular unleaded (91),premium unleaded(95),regular diesel,premium diesel',
            'liters' => 'nullable|numeric|min:1',
            'budget' => 'nullable|numeric|min:1',
            'purchase_mode' => 'nullable|string|in:liters,budget',
            'fuel_efficiency' => 'nullable|numeric|min:1',
            'idling_rate' => 'nullable|numeric',
            'preferred_brand' => 'nullable|string',
            'price_sensitivity' => 'nullable|string|in:high,medium,low',
        ]);

        $lat = (double)$fields['latitude'];
        $lng = (double)$fields['longitude'];
        $fuelType = $fields['fuel_type'];
        
        $purchaseMode = $fields['purchase_mode'] ?? 'liters';
        $budget = isset($fields['budget']) ? (double)$fields['budget'] : null;
        $liters = (double)($fields['liters'] ?? 30.0);
        
        $user = $request->user();
        
        $efficiency = 12.5;
        if ($user && $user->vehicle) {
            $efficiency = (double)$user->vehicle->fuel_efficiency;
        } elseif (isset($fields['fuel_efficiency'])) {
            $efficiency = (double)$fields['fuel_efficiency'];
        }

        $idlingRate = 1.2;
        if ($user && $user->vehicle) {
            $idlingRate = (double)$user->vehicle->idling_rate;
        } elseif (isset($fields['idling_rate'])) {
            $idlingRate = (double)$fields['idling_rate'];
        }

        $excludeUserId = $user ? $user->id : null;

        $routingResults = $this->routingEngine->computeOptimalRoutes(
            $lat,
            $lng,
            $fuelType,
            $liters,
            $budget,
            $fields['purchase_mode'] ?? 'liters',
            $efficiency,
            $idlingRate,
            $excludeUserId,
            $fields['preferred_brand'] ?? null,
            $fields['price_sensitivity'] ?? null
        );

        if (empty($routingResults) || empty($routingResults['stations'])) {
            return response(['message' => 'No active gas stations or prices found for the requested fuel type.'], 404);
        }

        return response($routingResults, 200);
    }

    // POST /api/gas-stations/{id}/queue (Motorist manual queue condition report)
    public function updateQueue(Request $request, $id)
    {
        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Gas station not found.'], 404);
        }

        $fields = $request->validate([
            'queue_count'       => 'required|integer|min:0',
            'wait_time_minutes' => 'nullable|numeric|min:0',
            'latitude'          => 'nullable|numeric',
            'longitude'         => 'nullable|numeric',
        ]);

        if (isset($fields['latitude']) && isset($fields['longitude'])) {
            if (!$this->validateDavaoCoordinates((float)$fields['latitude'], (float)$fields['longitude'])) {
                return response(['message' => 'Location coordinates must be within Davao City geographical boundaries.'], 422);
            }
        }

        // Strict Geofence verification: Motorist must be within station perimeter (~100m) to update queue
        $user = $request->user();
        if ($user && $user->role === 'motorist') {
            if (isset($fields['latitude']) && isset($fields['longitude'])) {
                $userLat = (float)$fields['latitude'];
                $userLng = (float)$fields['longitude'];
                $distance = $this->priceValidator->haversine($userLat, $userLng, (float)$station->latitude, (float)$station->longitude);
                $insideGeofence = $this->priceValidator->isPointInPolygon($userLat, $userLng, $station->geofence_polygon ?? []);
                if ($distance > 0.150 && !$insideGeofence) {
                    return response([
                        'message' => 'Geofence verification failed. You must be physically within range (~100m) of ' . $station->name . ' to submit queue reports.'
                    ], 422);
                }
            }
        }


        $queueCount = (int)$fields['queue_count'];
        $waitTime = isset($fields['wait_time_minutes']) ? (float)$fields['wait_time_minutes'] : ($queueCount * 3.0);

        $station->queue_count = $queueCount;
        $station->wait_time_minutes = $waitTime;
        $station->save();

        // Increment motorist trust score for reporting queue conditions
        $user = $request->user();
        if ($user && $user->role === 'motorist') {
            $user->trust_score = min(100, ($user->trust_score ?? 50) + 1);
            $user->save();
        }

        return response([
            'message'           => 'Queue condition reported successfully.',
            'station_id'        => $station->id,
            'queue_count'       => $station->queue_count,
            'wait_time_minutes' => $station->wait_time_minutes,
        ], 200);
    }

    // GET /api/gas-stations/live (Real-time responsiveness sync)
    public function liveUpdates(Request $request)
    {
        $excludeUserId = $request->user() ? $request->user()->id : null;
        $updates = GasStation::all()->map(function ($station) use ($excludeUserId) {
            $queueData = $this->queueEstimator->calculateStationQueue($station->id, $excludeUserId);
            $priceData = $this->getStationPrices($station->id);
            return [
                'id'                => $station->id,
                'status'            => $station->status,
                'fuel_availability' => $station->fuel_availability ?? [],
                'queue_count'       => $queueData['queue_count'],
                'wait_time_minutes' => $queueData['wait_time_minutes'],
                'prices'            => $priceData['prices'],
                'price_credibility' => $priceData['credibility'],
                'timestamp'         => now()->toIso8601String(),
            ];
        });

        return response($updates, 200);
    }

    // GET /api/price-submissions (Admin Summary of All Submitted Fuel Prices)
    public function getAllSubmissions()
    {
        $prices = FuelPrice::with(['station', 'reporter', 'anomalyLogs'])
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(function ($fp) {
                $anomaly = $fp->anomalyLogs->first();
                $calculatedStatus = 'pending';

                if ($anomaly && $anomaly->status === 'dismissed') {
                    $calculatedStatus = 'rejected';
                } elseif ($anomaly && $anomaly->status === 'resolved') {
                    $calculatedStatus = 'approved';
                } elseif ($anomaly && $anomaly->status === 'pending') {
                    $calculatedStatus = 'pending';
                } elseif ($fp->status === 'merchant_verified' || $fp->ocr_verified) {
                    $calculatedStatus = 'verified';
                } elseif ($fp->is_inside_geofence) {
                    $calculatedStatus = 'verified';
                } else {
                    $calculatedStatus = 'pending';
                }

                return [
                    'id'                 => $fp->id,
                    'station_id'         => $fp->station_id,
                    'station_name'       => $fp->station ? $fp->station->name : 'Unknown Station',
                    'station_branch'     => $fp->station ? $fp->station->branch : 'Main',
                    'fuel_type'          => $fp->fuel_type,
                    'price'              => (float)$fp->price,
                    'reported_by'        => $fp->reported_by,
                    'reporter_name'      => $fp->reporter ? $fp->reporter->name : 'Motorist',
                    'trust_score'        => $fp->reporter ? $fp->reporter->trust_score : 50,
                    'status'             => $fp->status,
                    'ocr_verified'       => (bool)$fp->ocr_verified,
                    'is_inside_geofence' => (bool)$fp->is_inside_geofence,
                    'calculated_status'  => $calculatedStatus,
                    'image_path'         => $fp->image_path,
                    'created_at'         => $fp->created_at ? \Carbon\Carbon::parse($fp->created_at)->toIso8601String() : now()->toIso8601String(),
                    'anomaly_id'         => $anomaly ? $anomaly->id : null,
                ];
            });

        return response($prices, 200);
    }

    // POST /api/price-submissions/{id}/approve
    public function approveSubmission($id)
    {
        $fp = FuelPrice::find($id);
        if (!$fp) {
            return response(['message' => 'Price submission not found'], 404);
        }

        $fp->is_inside_geofence = true;
        $fp->save();

        $anomalies = AnomalyLog::where('price_id', $fp->id)->get();
        foreach ($anomalies as $anomaly) {
            $anomaly->status = 'resolved';
            $anomaly->save();
        }

        if ($fp->reporter && $fp->reporter->role === 'motorist') {
            $fp->reporter->trust_score = min(100, $fp->reporter->trust_score + 5);
            $fp->reporter->save();
        }

        return response(['message' => 'Price submission approved & verified successfully.'], 200);
    }

    // POST /api/price-submissions/{id}/reject
    public function rejectSubmission($id)
    {
        $fp = FuelPrice::find($id);
        if (!$fp) {
            return response(['message' => 'Price submission not found'], 404);
        }

        $anomaly = AnomalyLog::where('price_id', $fp->id)->first();
        if (!$anomaly) {
            AnomalyLog::create([
                'id'          => (string) Str::uuid(),
                'station_id'  => $fp->station_id,
                'price_id'    => $fp->id,
                'description' => 'Price submission rejected manually by administrator.',
                'status'      => 'dismissed',
            ]);
        } else {
            $anomaly->status = 'dismissed';
            $anomaly->save();
        }

        if ($fp->reporter && $fp->reporter->role === 'motorist') {
            $fp->reporter->trust_score = max(0, $fp->reporter->trust_score - 10);
            $fp->reporter->save();
        }

        return response(['message' => 'Price submission rejected.'], 200);
    }
}
