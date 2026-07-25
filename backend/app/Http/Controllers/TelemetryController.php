<?php

namespace App\Http\Controllers;

use App\Models\GasStation;
use App\Models\TelemetryLog;
use Illuminate\Http\Request;

class TelemetryController extends Controller
{
    // Ray-Casting Point in Polygon check
    private function isPointInPolygon($lat, $lng, $polygon)
    {
        if (empty($polygon)) return false;
        $inside = false;
        $numPoints = count($polygon);
        for ($i = 0, $j = $numPoints - 1; $i < $numPoints; $j = $i++) {
            $latI = $polygon[$i][0];
            $lngI = $polygon[$i][1];
            $latJ = $polygon[$j][0];
            $lngJ = $polygon[$j][1];

            $intersect = (($lngI > $lng) != ($lngJ > $lng))
                && ($lat < ($latJ - $latI) * ($lng - $lngI) / ($lngJ - $lngI) + $latI);
            if ($intersect) $inside = !$inside;
        }
        return $inside;
    }

    // POST /api/telemetry
    public function log(Request $request)
    {
        $fields = $request->validate([
            'latitude' => 'required|numeric',
            'longitude' => 'required|numeric',
            'velocity' => 'required|numeric', // km/h
            'mock_user_id' => 'nullable|string',
        ]);

        $lat = (double)$fields['latitude'];
        $lng = (double)$fields['longitude'];
        $velocity = (double)$fields['velocity'];

        // Davao City geographical bounding box validation
        if ($lat < 6.8500 || $lat > 7.5500 || $lng < 125.2500 || $lng > 125.8500) {
            return response(['message' => 'Telemetry coordinates must be within Davao City geographical boundaries.'], 422);
        }
        
        $user = $request->user();
        $userId = $fields['mock_user_id'] ?? ($user ? $user->id : null);

        // Check if motorist is inside any station's geofence
        $stations = GasStation::all();
        $matchedStationId = null;
        $isInsideFence = false;

        foreach ($stations as $station) {
            if ($this->isPointInPolygon($lat, $lng, $station->geofence_polygon)) {
                $matchedStationId = $station->id;
                $isInsideFence = true;
                break;
            }
        }

        $log = TelemetryLog::create([
            'user_id' => $userId,
            'station_id' => $matchedStationId,
            'velocity' => $velocity,
            'is_inside_fence' => $isInsideFence,
            'timestamp' => now(),
        ]);

        return response([
            'message' => 'Telemetry logged successfully',
            'log' => $log,
            'matched_station_id' => $matchedStationId,
            'is_inside_fence' => $isInsideFence,
        ], 201);
    }

    // POST /api/telemetry/flush
    public function flush()
    {
        TelemetryLog::query()->delete();
        return response(['message' => 'Telemetry logs cleared successfully'], 200);
    }
}
