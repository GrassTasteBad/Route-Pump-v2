<?php

namespace App\Http\Controllers;

use App\Models\AnomalyLog;
use App\Models\FuelPrice;
use Illuminate\Http\Request;

class AnomalyController extends Controller
{
    // GET /api/anomalies
    public function index()
    {
        $anomalies = AnomalyLog::with(['station', 'price.reporter'])
            ->orderBy('created_at', 'desc')
            ->get();

        $grouped = [];

        foreach ($anomalies as $log) {
            $fp = $log->price;
            if (!$fp) {
                $grouped['single_' . $log->id] = [$log];
                continue;
            }

            if (!empty($fp->batch_id)) {
                $groupKey = 'batch_' . $fp->batch_id;
            } elseif (!empty($fp->image_path)) {
                $groupKey = 'img_' . $fp->image_path;
            } elseif ($fp->created_at) {
                $timeBucket = floor(\Carbon\Carbon::parse($fp->created_at)->timestamp / 10);
                $groupKey = 'time_' . $fp->station_id . '_' . $fp->reported_by . '_' . $timeBucket;
            } else {
                $groupKey = 'single_' . $log->id;
            }

            if (!isset($grouped[$groupKey])) {
                $grouped[$groupKey] = [];
            }
            $grouped[$groupKey][] = $log;
        }

        $reports = [];

        foreach ($grouped as $group) {
            $primary = $group[0];
            $primaryPrice = $primary->price;
            $variants = [];
            $hasPending = false;
            $hasResolved = false;
            $hasDismissed = false;

            foreach ($group as $item) {
                $itemFp = $item->price;
                if ($item->status === 'pending') $hasPending = true;
                if ($item->status === 'resolved') $hasResolved = true;
                if ($item->status === 'dismissed') $hasDismissed = true;

                $variants[] = [
                    'anomaly_id'   => $item->id,
                    'price_id'     => $itemFp ? $itemFp->id : null,
                    'fuel_type'    => $itemFp ? $itemFp->fuel_type : 'Fuel',
                    'price'        => $itemFp ? (float)$itemFp->price : 0,
                    'status'       => $item->status,
                    'price_status' => $itemFp ? $itemFp->status : null,
                    'ocr_verified' => $itemFp ? (bool)$itemFp->ocr_verified : false,
                ];
            }

            $overallStatus = $hasPending ? 'pending' : ($hasResolved ? 'resolved' : 'dismissed');

            $reports[] = [
                'id'           => $primary->id,
                'anomaly_ids'  => array_map(fn($item) => $item->id, $group),
                'station_id'   => $primary->station_id,
                'station'      => $primary->station,
                'price_id'     => $primary->price_id,
                'price'        => $primaryPrice,
                'image_path'   => $primaryPrice ? $primaryPrice->image_path : null,
                'description'  => $primary->description,
                'status'       => $overallStatus,
                'created_at'   => $primary->created_at,
                'updated_at'   => $primary->updated_at,
                'variants'     => $variants,
            ];
        }

        return response($reports, 200);
    }

    // Helper to find all related prices in the same submission/batch
    private function getRelatedPrices(AnomalyLog $anomaly)
    {
        if (!$anomaly->price) {
            return collect();
        }

        $fp = $anomaly->price;

        if (!empty($fp->batch_id)) {
            return FuelPrice::where('batch_id', $fp->batch_id)->get();
        }

        if (!empty($fp->image_path)) {
            return FuelPrice::where('image_path', $fp->image_path)->get();
        }

        if ($fp->created_at) {
            $range = FuelPrice::where('station_id', $fp->station_id)
                ->where('reported_by', $fp->reported_by)
                ->whereBetween('created_at', [
                    \Carbon\Carbon::parse($fp->created_at)->subSeconds(10),
                    \Carbon\Carbon::parse($fp->created_at)->addSeconds(10)
                ])
                ->get();
            if ($range->count() > 1) {
                return $range;
            }
        }

        return collect([$fp]);
    }

    // POST /api/anomalies/{id}/resolve
    public function resolve($id)
    {
        $anomaly = AnomalyLog::find($id);
        if (!$anomaly) {
            return response(['message' => 'Anomaly log not found'], 404);
        }

        $relatedPrices = $this->getRelatedPrices($anomaly);
        if ($relatedPrices->isEmpty() && $anomaly->price) {
            $relatedPrices = collect([$anomaly->price]);
        }

        foreach ($relatedPrices as $fp) {
            if ($fp->status === 'pending_photo_review') {
                $fp->status = 'crowdsourced';
            }
            $fp->is_inside_geofence = true;
            $fp->save();

            AnomalyLog::where('price_id', $fp->id)
                ->where('status', 'pending')
                ->update(['status' => 'resolved']);
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
            'message' => 'Report approved. Fuel prices are verified and published live for motorists.',
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

        $relatedPrices = $this->getRelatedPrices($anomaly);
        if ($relatedPrices->isEmpty() && $anomaly->price) {
            $relatedPrices = collect([$anomaly->price]);
        }

        foreach ($relatedPrices as $fp) {
            AnomalyLog::where('price_id', $fp->id)
                ->where('status', 'pending')
                ->update(['status' => 'dismissed']);
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

        return response([
            'message' => 'Report dismissed. The submitted prices were rejected.',
            'anomaly' => $anomaly->load('station', 'price.reporter'),
        ], 200);
    }
}
