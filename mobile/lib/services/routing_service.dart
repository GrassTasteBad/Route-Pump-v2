import '../models/gas_station.dart';
import '../models/vehicle_profile.dart';
import 'api_service.dart';

class RoutingService {
  /**
     * Checks if the given time is rush hour (7:30-9:00 AM, 5:00-6:30 PM) in Davao City.
     */
  static bool isRushHour() {
    final now = DateTime.now();
    final hour = now.hour;
    final minute = now.minute;
    final timeDecimal = hour + (minute / 60.0);

    return (timeDecimal >= 7.5 && timeDecimal <= 9.0) || (timeDecimal >= 17.0 && timeDecimal <= 18.5);
  }

  /**
   * Computes refueling routes locally based on the relative net savings formula.
   */
  static Map<String, dynamic>? computeOptimalRoutes({
    required double motoristLat,
    required double motoristLng,
    required String fuelType,
    required String purchaseMode,
    required double liters,
    required double? budget,
    required VehicleProfile? vehicle,
    required List<GasStation> stations,
    String? preferredBrand,
    String? priceSensitivity,
  }) {
    double eff = vehicle?.fuelEfficiency ?? 12.5;
    double idlingRate = vehicle?.idlingRate ?? 1.2;
    bool useBudgetMode = (purchaseMode == 'budget' && budget != null && budget > 0);

    // Detour weighting factor: High sensitivity = 0.5, Medium = 1.0, Low = 2.0
    double sensitivityFactor = 1.0;
    if (priceSensitivity != null) {
      final sLower = priceSensitivity.toLowerCase();
      if (sLower == 'high') {
        sensitivityFactor = 0.5;
      } else if (sLower == 'low') {
        sensitivityFactor = 2.0;
      }
    }

    // 0. Filter stations by preferred brand
    final filtered = stations.where((s) {
      if (preferredBrand == null || preferredBrand.toLowerCase() == 'all') {
        return true;
      }
      return s.name.toLowerCase().contains(preferredBrand.toLowerCase());
    }).toList();

    if (filtered.isEmpty) return null;

    // 1. Find closest active station as baseline from filtered stations
    GasStation? baseline;
    double minDist = double.infinity;
    for (var s in filtered) {
      if (s.prices[fuelType] == null || s.status != 'active') continue;
      double dist = AppState().getHaversineDistance(motoristLat, motoristLng, s.latitude, s.longitude);
      if (dist < minDist) {
        minDist = dist;
        baseline = s;
      }
    }

    if (baseline == null) return null;
    double basePrice = baseline.prices[fuelType]!;

    // 2. Pre-calculate travel cost for the baseline station (scaled by detour sensitivity)
    double baselineRawDist = AppState().getHaversineDistance(motoristLat, motoristLng, baseline.latitude, baseline.longitude);
    double baselineStreetDist = baselineRawDist * 1.3;
    double trafficFactor = isRushHour() ? 1.8 : 1.2;
    double baselineEffectiveDist = baselineStreetDist * trafficFactor;
    double baselineIdleHours = (baseline.queueCount * 3.0) / 60.0;
    
    double baselineFuelDriving = baselineEffectiveDist / eff;
    double baselineFuelIdling = baselineIdleHours * idlingRate;
    double baselineTotalFuel = baselineFuelDriving + baselineFuelIdling;
    double cTravelBaseline = baselineTotalFuel * basePrice * sensitivityFactor;

    // 3. Evaluate each station
    List<Map<String, dynamic>> stationsList = [];
    for (var s in filtered) {
      if (s.prices[fuelType] == null || s.status != 'active') continue;
      
      double rawDist = AppState().getHaversineDistance(motoristLat, motoristLng, s.latitude, s.longitude);
      double streetDist = rawDist * 1.3;
      double effectiveDist = streetDist * trafficFactor;

      double tIdleHours = (s.queueCount * 3.0) / 60.0;
      double price = s.prices[fuelType]!;

      double fuelDriving = effectiveDist / eff;
      double fuelIdling = tIdleHours * idlingRate;
      double travelCost = (fuelDriving + fuelIdling) * price * sensitivityFactor;

      double grossSavings = 0.0;
      double displayLiters = liters;
      if (useBudgetMode) {
        double targetLiters = budget / price;
        double baselineLiters = budget / basePrice;
        grossSavings = (targetLiters - baselineLiters) * price;
        displayLiters = targetLiters;
      } else {
        grossSavings = liters * (basePrice - price);
        displayLiters = liters;
      }

      // Relative net savings formula: S_net = Gross_Savings - (C_travel_target - C_travel_baseline)
      double netSavings = grossSavings - (travelCost - cTravelBaseline);

      final pathNodes = [
        {'name': 'Start', 'lat': motoristLat, 'lng': motoristLng},
        {'name': '${s.name} - ${s.branch}', 'lat': s.latitude, 'lng': s.longitude},
      ];

      stationsList.add({
        'station_id': s.id,
        'name': s.name,
        'branch': s.branch,
        'latitude': s.latitude,
        'longitude': s.longitude,
        'price': price,
        'prices': s.prices,
        'raw_distance_km': rawDist,
        'effective_distance_km': effectiveDist,
        'queue_count': s.queueCount,
        'wait_time_minutes': s.queueCount * 3.0,
        'fuel_burned_driving_liters': fuelDriving,
        'fuel_burned_idling_liters': fuelIdling,
        'travel_cost_php': travelCost,
        'gross_savings_php': grossSavings,
        'net_savings_php': netSavings,
        'liters_purchased': displayLiters,
        'path_nodes': pathNodes,
        'is_baseline': s.id == baseline.id,
      });
    }

    // Sort by Net Savings descending
    stationsList.sort((a, b) => (b['net_savings_php'] as num).compareTo(a['net_savings_php'] as num));

    return {
      'baseline_station_id': baseline.id,
      'baseline_price': basePrice,
      'liters': liters,
      'fuel_efficiency_kml': eff,
      'traffic_factor': trafficFactor,
      'rush_hour': isRushHour(),
      'stations': stationsList,
    };
  }
}
