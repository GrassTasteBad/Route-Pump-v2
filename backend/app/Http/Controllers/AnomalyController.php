<?php

namespace App\Http\Controllers;

use App\Models\AnomalyLog;
use Illuminate\Http\Request;

class AnomalyController extends Controller
{
    // GET /api/anomalies
    public function index()
    {
        $anomalies = AnomalyLog::with(['station', 'price.reporter'])
            ->orderBy('created_at', 'desc')
            ->get();

        return response($anomalies, 200);
    }

    // POST /api/anomalies/{id}/resolve
    public function resolve($id)
    {
        $anomaly = AnomalyLog::find($id);
        if (!$anomaly) {
            return response(['message' => 'Anomaly log not found'], 404);
        }

        $anomaly->status = 'resolved';
        $anomaly->save();

        if ($anomaly->price && $anomaly->price->reporter) {
            $reporter = $anomaly->price->reporter;
            if ($reporter->role === 'motorist') {
                $reporter->trust_score = min(100, $reporter->trust_score + 10);
                $reporter->save();
            }
        }

        return response([
            'message' => 'Anomaly resolved. The crowdsourced price has been approved and published.',
            'anomaly' => $anomaly->load('station', 'price'),
        ], 200);
    }

    // POST /api/anomalies/{id}/dismiss
    public function dismiss($id)
    {
        $anomaly = AnomalyLog::find($id);
        if (!$anomaly) {
            return response(['message' => 'Anomaly log not found'], 404);
        }

        $anomaly->status = 'dismissed';
        $anomaly->save();

        if ($anomaly->price && $anomaly->price->reporter) {
            $reporter = $anomaly->price->reporter;
            if ($reporter->role === 'motorist') {
                $reporter->trust_score = max(0, $reporter->trust_score - 15);
                $reporter->save();
            }
        }

        // We do not delete the price record so that the anomaly history is preserved.
        // The price is deactivated because we exclude dismissed anomalies from active prices.

        return response([
            'message' => 'Anomaly dismissed. The fraudulent price submission has been rejected and deactivated.',
            'anomaly' => $anomaly->load('station', 'price.reporter'),
        ], 200);
    }
}
