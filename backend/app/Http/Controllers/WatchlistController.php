<?php

namespace App\Http\Controllers;

use App\Models\GasStation;
use App\Models\Watchlist;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class WatchlistController extends Controller
{
    /**
     * Get user's favorites watchlist with active fuel prices.
     */
    public function index(Request $request)
    {
        $user = $request->user();
        $watchlists = Watchlist::where('user_id', $user->id)
            ->with(['station.prices' => function($q) {
                $q->orderBy('created_at', 'desc');
            }])
            ->get();

        $stations = [];
        foreach ($watchlists as $item) {
            if ($item->station) {
                $station = $item->station;
                
                // Construct the active prices dictionary
                $activePrices = [];
                foreach (['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel'] as $type) {
                    $latestPrice = $station->prices()
                        ->where('fuel_type', $type)
                        ->orderBy('created_at', 'desc')
                        ->first();
                    
                    if ($latestPrice) {
                        $activePrices[$type] = [
                            'price' => (double)$latestPrice->price,
                            'status' => $latestPrice->status,
                            'created_at' => $latestPrice->created_at->toDateTimeString(),
                            'ocr_verified' => (bool)$latestPrice->ocr_verified,
                        ];
                    } else {
                        $activePrices[$type] = null;
                    }
                }

                $stations[] = [
                    'id' => $station->id,
                    'name' => $station->name,
                    'branch' => $station->branch,
                    'address' => $station->address,
                    'latitude' => (double)$station->latitude,
                    'longitude' => (double)$station->longitude,
                    'active_prices' => $activePrices,
                    'watchlist_item_id' => $item->id,
                ];
            }
        }

        return response()->json($stations);
    }

    /**
     * Add a station to the watchlist.
     */
    public function store(Request $request)
    {
        $fields = $request->validate([
            'station_id' => 'required|uuid|exists:gas_stations,id',
        ]);

        $user = $request->user();

        // Check if already in watchlist
        $exists = Watchlist::where('user_id', $user->id)
            ->where('station_id', $fields['station_id'])
            ->first();

        if ($exists) {
            return response(['message' => 'Station already in watchlist', 'id' => $exists->id], 200);
        }

        $item = Watchlist::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'station_id' => $fields['station_id'],
        ]);

        return response($item, 201);
    }

    /**
     * Remove a station from the watchlist.
     */
    public function destroy(Request $request, $stationId)
    {
        $user = $request->user();
        $deleted = Watchlist::where('user_id', $user->id)
            ->where('station_id', $stationId)
            ->delete();

        if ($deleted) {
            return response(['message' => 'Station removed from watchlist'], 200);
        }

        return response(['message' => 'Not found in watchlist'], 404);
    }
}
