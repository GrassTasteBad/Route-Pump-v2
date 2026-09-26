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
        $station = GasStation::find($id);
        if (!$station) {
            return response(['message' => 'Station not found'], 404);
        }

        // 1. Parse fuel prices — supports both multi-variant batch ('prices') and single ('fuel_type' + 'price')
        $prices = [];
        if ($request->has('prices')) {
            $rawPrices = $request->input('prices');
            if (is_string($rawPrices)) {
                $decoded = json_decode($rawPrices, true);
                $prices = is_array($decoded) ? $decoded : [];
            } elseif (is_array($rawPrices)) {
                $prices = $rawPrices;
            }
        } elseif ($request->filled('fuel_type') && $request->filled('price')) {
            $prices = [$request->input('fuel_type') => $request->input('price')];
        }

        $validTypes = ['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel'];
        $sanitizedPrices = [];
        foreach ($prices as $type => $price) {
            $normalizedType = strtolower(trim((string)$type));
            if (in_array($normalizedType, $validTypes) && is_numeric($price) && (float)$price >= 1) {
                $sanitizedPrices[$normalizedType] = (float)$price;
            }
        }

        if (empty($sanitizedPrices)) {
            return response(['message' => 'Please provide at least one valid fuel type and price.'], 422);
        }

        $user = $request->user();

        // 2. Determine status
        // Partner/admin submissions go live immediately as merchant_verified.
        // Motorist photo submissions are held as pending_photo_review until an admin
        // explicitly approves them — they never auto-publish.
        $isPhotoSubmission = $request->hasFile('photo');
        $status = 'crowdsourced';
        if (($user->role === 'partner' && $user->station_id === $station->id) || $user->role === 'admin') {
            $status = 'merchant_verified';
        } elseif ($isPhotoSubmission) {
            // Motorist with a photo: hold for admin approval before going live
            $status = 'pending_photo_review';
        }

        // 3. Geofence evaluation: Determine if submission is within geofence range (~150m or polygon)
        $isInsideGeofence = true;
        if ($request->filled('latitude') && $request->filled('longitude')) {
            $userLat = (float)$request->input('latitude');
            $userLng = (float)$request->input('longitude');
            $distance = $this->priceValidator->haversine($userLat, $userLng, (float)$station->latitude, (float)$station->longitude);
            $insidePolygon = $this->priceValidator->isPointInPolygon($userLat, $userLng, $station->geofence_polygon ?? []);
            $isInsideGeofence = ($distance <= 0.150 || $insidePolygon);
        }

        // 4. Single Photo upload & OCR verification for all fuel variants
        $ocrVerified = false;
        $imagePath = null;
        if ($isPhotoSubmission) {
            $photo = $request->file('photo');
            $imagePath = $photo->store('proofs', 'public');
            // Run OCR to check it's a genuine price board — but this does NOT auto-approve
            $firstPrice = (double)reset($sanitizedPrices);
            $extractedPrice = $this->ocrService->extractPrice($imagePath, $firstPrice);
            if ($extractedPrice !== null) {
                $ocrVerified = true;
            }
        }

        $batchId = (string) Str::uuid();
        $createdRecords = [];
        $hasAnomaly = false;

        // 5. Create FuelPrice records for every fuel variant in this single submission
        foreach ($sanitizedPrices as $fuelType => $price) {
            // Check for exact duplicate submission by same user for same station & fuel type within 2 minutes
            $recentDuplicate = FuelPrice::where('station_id', $station->id)
                ->where('fuel_type', $fuelType)
                ->where('reported_by', $user->id)
                ->where('price', $price)
                ->where('created_at', '>=', now()->subMinutes(2))
                ->first();

            if ($recentDuplicate) {
                $createdRecords[] = $recentDuplicate;
                continue;
            }

            $priceRecord = FuelPrice::create([
                'id' => (string) Str::uuid(),
                'batch_id' => $batchId,
                'station_id' => $station->id,
                'fuel_type' => $fuelType,
                'price' => $price,
                'reported_by' => $user->id,
                'status' => $status,
                'created_at' => now(),
                'image_path' => $imagePath,
                'ocr_verified' => $ocrVerified,
                'is_inside_geofence' => $isInsideGeofence,
            ]);

            // Photo submissions by motorists: always create an AnomalyLog so admin
            // must explicitly approve or reject before the price goes live.
            if ($status === 'pending_photo_review') {
                $ocrNote = $ocrVerified ? 'OCR detected a valid price board. ' : '';
                AnomalyLog::create([
                    'id'          => (string) Str::uuid(),
                    'station_id'  => $station->id,
                    'price_id'    => $priceRecord->id,
                    'description' => $ocrNote . 'Motorist submitted prices with a photo — awaiting admin image audit and approval before publishing.',
                    'status'      => 'pending',
                ]);
                $hasAnomaly = true;
            // Regular crowdsourced submission: run anomaly detection as usual
            } elseif ($status === 'crowdsourced') {
                $anomalyResult = $this->priceValidator->checkPriceAnomaly(
                    $station->id,
                    $fuelType,
                    (double)$price,
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
                    $hasAnomaly = true;
                }
            } else {
                // Partner/Admin override: resolve pending anomaly logs for this station and fuel type
                $pendingAnomalies = AnomalyLog::where('station_id', $station->id)
                    ->where('status', 'pending')
                    ->whereHas('price', function ($q) use ($fuelType) {
                        $q->where('fuel_type', $fuelType);
                    })->get();

                foreach ($pendingAnomalies as $anomaly) {
                    $anomaly->status = 'resolved';
                    $anomaly->save();
                }

                FuelPrice::where('station_id', $station->id)
                    ->where('fuel_type', $fuelType)
                    ->where('status', 'crowdsourced')
                    ->delete();
            }

            $createdRecords[] = $priceRecord;
        }

        // Trust score bonus only for clean crowdsourced reports (not pending review)
        if ($status === 'crowdsourced' && !$hasAnomaly && $user->role === 'motorist') {
            $user->trust_score = min(100, $user->trust_score + 2);
            $user->save();
        }

        $primaryRecord = !empty($createdRecords) ? $createdRecords[0] : null;

        $responseMessage = $status === 'pending_photo_review'
            ? 'Photo submission received. An admin will review and approve your prices before they go live.'
            : ($isInsideGeofence
                ? 'Price(s) updated successfully.'
                : 'Recorded successfully. Waiting for other motorists to submit matching prices.');

        return response([
            'message'            => $responseMessage,
            'batch_id'           => $batchId,
            'price'              => $primaryRecord,
            'prices'             => $createdRecords,
            'anomaly_flagged'    => $hasAnomaly,
            'is_inside_geofence' => $isInsideGeofence,
            'pending_review'     => $status === 'pending_photo_review',
        ], $hasAnomaly ? 202 : 201);
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

    // Helper to find all related prices in the same submission
    private function getRelatedPrices(string $id)
    {
        $fp = FuelPrice::find($id);
        if (!$fp) {
            return FuelPrice::where('batch_id', $id)->get();
        }

        if (!empty($fp->batch_id)) {
            return FuelPrice::where('batch_id', $fp->batch_id)->get();
        }

        if (!empty($fp->image_path)) {
            $byImg = FuelPrice::where('image_path', $fp->image_path)->get();
            if ($byImg->count() > 1) return $byImg;
        }

        if ($fp->created_at) {
            $timeRange = FuelPrice::where('station_id', $fp->station_id)
                ->where('reported_by', $fp->reported_by)
                ->whereBetween('created_at', [
                    \Carbon\Carbon::parse($fp->created_at)->subSeconds(10),
                    \Carbon\Carbon::parse($fp->created_at)->addSeconds(10)
                ])
                ->get();
            if ($timeRange->count() > 0) return $timeRange;
        }

        return collect([$fp]);
    }

    // GET /api/price-submissions (Admin Summary of All Submitted Fuel Prices)
    public function getAllSubmissions()
    {
        $prices = FuelPrice::with(['station', 'reporter', 'anomalyLogs'])
            ->orderBy('created_at', 'desc')
            ->get();

        $grouped = [];

        foreach ($prices as $fp) {
            $timeBucket = $fp->created_at ? floor(\Carbon\Carbon::parse($fp->created_at)->timestamp / 10) : 0;

            if (!empty($fp->batch_id)) {
                $groupKey = 'batch_' . $fp->batch_id;
            } elseif (!empty($fp->image_path)) {
                $groupKey = 'img_' . $fp->image_path;
            } elseif ($fp->created_at) {
                $groupKey = 'time_' . $fp->station_id . '_' . $fp->reported_by . '_' . $timeBucket;
            } else {
                $groupKey = 'single_' . $fp->id;
            }

            // Also check if an earlier record with image_path from same station + reporter within 10s exists
            // to group legacy submissions that generated separate photos for each variant
            if (!empty($fp->image_path)) {
                foreach ($grouped as $k => $records) {
                    $firstRec = $records[0];
                    if (!empty($firstRec->image_path) &&
                        $firstRec->station_id === $fp->station_id &&
                        $firstRec->reported_by === $fp->reported_by &&
                        abs(\Carbon\Carbon::parse($firstRec->created_at)->diffInSeconds(\Carbon\Carbon::parse($fp->created_at))) <= 10) {
                        $groupKey = $k;
                        break;
                    }
                }
            }

            if (!isset($grouped[$groupKey])) {
                $grouped[$groupKey] = [];
            }
            $grouped[$groupKey][] = $fp;
        }

        $submissions = [];

        foreach ($grouped as $group) {
            $primary = $group[0];
            $variants = [];
            $hasPendingAnomaly = false;
            $hasDismissedAnomaly = false;
            $hasResolvedAnomaly = false;
            $allVerified = true;
            $anyInsideGeofence = false;
            $anyOcrVerified = false;
            $primaryAnomalyId = null;

            foreach ($group as $fp) {
                $anomaly = $fp->anomalyLogs->first();
                if ($anomaly && !$primaryAnomalyId) {
                    $primaryAnomalyId = $anomaly->id;
                }

                $variantStatus = 'pending';
                if ($fp->status === 'pending_photo_review') {
                    // Held for admin image audit — not yet live
                    $variantStatus = 'pending_photo_review';
                    $hasPendingAnomaly = true;
                    $allVerified = false;
                } elseif ($anomaly && $anomaly->status === 'dismissed') {
                    $variantStatus = 'rejected';
                    $hasDismissedAnomaly = true;
                    $allVerified = false;
                } elseif ($anomaly && $anomaly->status === 'resolved') {
                    $variantStatus = 'approved';
                    $hasResolvedAnomaly = true;
                } elseif ($anomaly && $anomaly->status === 'pending') {
                    $variantStatus = 'pending';
                    $hasPendingAnomaly = true;
                    $allVerified = false;
                } elseif ($fp->status === 'merchant_verified' || $fp->ocr_verified || $fp->is_inside_geofence) {
                    $variantStatus = 'verified';
                } else {
                    $variantStatus = 'pending';
                    $allVerified = false;
                }

                if ($fp->is_inside_geofence) $anyInsideGeofence = true;
                if ($fp->ocr_verified) $anyOcrVerified = true;

                $variants[] = [
                    'id'                => $fp->id,
                    'fuel_type'         => $fp->fuel_type,
                    'price'             => (float)$fp->price,
                    'status'            => $fp->status,
                    'calculated_status' => $variantStatus,
                    'ocr_verified'      => (bool)$fp->ocr_verified,
                    'anomaly_id'        => $anomaly ? $anomaly->id : null,
                ];
            }

            // Determine overall status — pending_photo_review takes priority
            $hasPendingPhotoReview = collect($group)->contains(fn($fp) => $fp->status === 'pending_photo_review');
            if ($hasPendingPhotoReview) {
                $overallStatus = 'pending_photo_review';
            } elseif ($hasPendingAnomaly) {
                $overallStatus = 'pending';
            } elseif ($hasDismissedAnomaly) {
                $overallStatus = 'rejected';
            } elseif ($hasResolvedAnomaly) {
                $overallStatus = 'approved';
            } elseif ($allVerified && ($anyInsideGeofence || $anyOcrVerified || $primary->status === 'merchant_verified')) {
                $overallStatus = 'verified';
            } else {
                $overallStatus = 'pending';
            }

            $fuelTypeLabel = count($variants) === 1
                ? $variants[0]['fuel_type']
                : implode(', ', array_map(function($v) { return $v['fuel_type']; }, $variants));

            $submissions[] = [
                'id'                 => $primary->id,
                'batch_id'           => $primary->batch_id,
                'price_ids'          => array_column($variants, 'id'),
                'station_id'         => $primary->station_id,
                'station_name'       => $primary->station ? $primary->station->name : 'Unknown Station',
                'station_branch'     => $primary->station ? $primary->station->branch : 'Main',
                'variants'           => $variants,
                'fuel_type'          => $fuelTypeLabel,
                'price'              => count($variants) === 1 ? $variants[0]['price'] : null,
                'reported_by'        => $primary->reported_by,
                'reporter_name'      => $primary->reporter ? $primary->reporter->name : 'Motorist',
                'trust_score'        => $primary->reporter ? $primary->reporter->trust_score : 50,
                'status'             => $primary->status,
                'ocr_verified'       => $anyOcrVerified,
                'is_inside_geofence' => $anyInsideGeofence,
                'calculated_status'  => $overallStatus,
                'image_path'         => $primary->image_path,
                'created_at'         => $primary->created_at ? \Carbon\Carbon::parse($primary->created_at)->toIso8601String() : now()->toIso8601String(),
                'anomaly_id'         => $primaryAnomalyId,
            ];
        }

        return response($submissions, 200);
    }

    // POST /api/price-submissions/{id}/approve
    public function approveSubmission($id)
    {
        $prices = $this->getRelatedPrices($id);
        if ($prices->isEmpty()) {
            return response(['message' => 'Price submission not found'], 404);
        }

        foreach ($prices as $fp) {
            // If this was a pending photo review, promote to crowdsourced so it goes live
            if ($fp->status === 'pending_photo_review') {
                $fp->status = 'crowdsourced';
            }
            $fp->is_inside_geofence = true; // Treat admin approval as geofence-verified
            $fp->save();

            // Resolve all anomaly/review logs for this price
            $anomalies = AnomalyLog::where('price_id', $fp->id)->get();
            foreach ($anomalies as $anomaly) {
                $anomaly->status = 'resolved';
                $anomaly->save();
            }
        }

        $reporter = $prices->first()->reporter;
        if ($reporter && $reporter->role === 'motorist') {
            $reporter->trust_score = min(100, $reporter->trust_score + 5);
            $reporter->save();
        }

        return response(['message' => 'Price submission approved — prices are now live for motorists.'], 200);
    }

    // POST /api/price-submissions/{id}/reject
    public function rejectSubmission($id)
    {
        $prices = $this->getRelatedPrices($id);
        if ($prices->isEmpty()) {
            return response(['message' => 'Price submission not found'], 404);
        }

        foreach ($prices as $fp) {
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
        }

        $reporter = $prices->first()->reporter;
        if ($reporter && $reporter->role === 'motorist') {
            $reporter->trust_score = max(0, $reporter->trust_score - 10);
            $reporter->save();
        }

        return response(['message' => 'Price submission rejected.'], 200);
    }
}
