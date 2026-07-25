<?php

namespace App\Http\Controllers;

use App\Models\FuelPrice;
use App\Models\Vehicle;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class AnalyticsController extends Controller
{
    /**
     * Return descriptive analytics for the admin panel dashboard.
     */
    public function dashboard(Request $request)
    {
        // 1. Fuel Type Distribution
        $fuelDistribution = FuelPrice::select('fuel_type', DB::raw('count(*) as count'))
            ->groupBy('fuel_type')
            ->get()
            ->pluck('count', 'fuel_type')
            ->toArray();

        $types = ['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel'];
        foreach ($types as $type) {
            if (!isset($fuelDistribution[$type])) {
                $fuelDistribution[$type] = 0;
            }
        }

        // 2. Participant Fuel Usage Patterns (average efficiency, vehicle count, fuel consumption stats)
        $avgEfficiency = (double) Vehicle::avg('fuel_efficiency') ?: 12.5;
        $totalVehicles = Vehicle::count();
        $totalUsers = User::count();
        $avgTrustScore = (double) User::avg('trust_score') ?: 50.0;

        // Group vehicles by efficiency range
        $efficiencyStats = [
            'efficient' => Vehicle::where('fuel_efficiency', '>=', 15.0)->count(),
            'moderate' => Vehicle::whereBetween('fuel_efficiency', [10.0, 14.99])->count(),
            'heavy' => Vehicle::where('fuel_efficiency', '<', 10.0)->count(),
        ];

        // 3. Localized Price Fluctuations (last 30 days)
        $priceTrendsRaw = FuelPrice::select(
                'fuel_type', 
                DB::raw('DATE(created_at) as date'), 
                DB::raw('AVG(price) as average_price')
            )
            ->groupBy('fuel_type', 'date')
            ->orderBy('date', 'asc')
            ->get();

        $priceTrends = [];
        foreach ($types as $type) {
            $priceTrends[$type] = [];
        }
        foreach ($priceTrendsRaw as $trend) {
            if (in_array($trend->fuel_type, $types)) {
                $priceTrends[$trend->fuel_type][] = [
                    'date' => $trend->date,
                    'price' => round((double)$trend->average_price, 2),
                ];
            }
        }

        return response()->json([
            'fuel_type_distribution' => $fuelDistribution,
            'vehicle_stats' => [
                'average_efficiency' => round($avgEfficiency, 2),
                'total_vehicles' => $totalVehicles,
                'efficiency_categories' => $efficiencyStats,
            ],
            'user_stats' => [
                'total_users' => $totalUsers,
                'average_trust_score' => round($avgTrustScore, 2),
            ],
            'price_trends' => $priceTrends,
        ]);
    }
}
