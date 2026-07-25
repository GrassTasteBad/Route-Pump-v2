<?php

namespace App\Services;

use App\Models\TelemetryLog;
use App\Models\User;
use Carbon\Carbon;

class QueueEstimator
{
    /**
     * Calculate queue size Q(t) and wait time for a given gas station.
     * Uses a 5-minute window of telemetry logs as per RoutePump.md.
     */
    public function calculateStationQueue(string $stationId, ?string $excludeUserId = null): array
    {
        // 5-minute window as specified in Equation 3 of RoutePump.md
        $fiveMinutesAgo = Carbon::now()->subMinutes(5);

        // Retrieve partner user ID linked to this station to exclude them from motorist queue counts
        $partnerUserId = User::where('station_id', $stationId)
            ->where('role', 'partner')
            ->value('id');

        $query = TelemetryLog::where('station_id', $stationId)
            ->where('is_inside_fence', true)
            ->where('velocity', '<', 5.0)
            ->where('timestamp', '>=', $fiveMinutesAgo);

        $excludeUserIds = [];
        if ($partnerUserId) {
            $excludeUserIds[] = $partnerUserId;
        }
        if ($excludeUserId) {
            $excludeUserIds[] = $excludeUserId;
        }

        if (!empty($excludeUserIds)) {
            $query->whereNotIn('user_id', $excludeUserIds);
        }

        $queueCount = $query->distinct('user_id')->count('user_id');

        // 3 minutes average service time per vehicle
        $waitTimeMinutes = $queueCount * 3.0;
        $waitTimeHours = $waitTimeMinutes / 60.0;

        return [
            'queue_count' => $queueCount,
            'wait_time_minutes' => $waitTimeMinutes,
            'wait_time_hours' => $waitTimeHours,
        ];
    }
}
