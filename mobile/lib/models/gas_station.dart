import 'dart:convert';

const List<String> kFuelTypes = [
  'regular unleaded (91)',
  'premium unleaded(95)',
  'regular diesel',
  'premium diesel',
];

class GasStation {
  final String id;
  final String name;
  final String branch;
  final double latitude;
  final double longitude;
  final List<List<double>> geofencePolygon;
  String status;
  int queueCount;
  double waitTimeMinutes;
  Map<String, double?> prices;
  /// Per-fuel-type availability toggled by the partner. true = available.
  Map<String, bool> fuelAvailability;

  GasStation({
    required this.id,
    required this.name,
    required this.branch,
    required this.latitude,
    required this.longitude,
    required this.geofencePolygon,
    required this.status,
    required this.queueCount,
    required this.waitTimeMinutes,
    required this.prices,
    Map<String, bool>? fuelAvailability,
  }) : fuelAvailability = fuelAvailability ?? {
    for (final t in kFuelTypes) t: true,
  };

  factory GasStation.fromJson(Map<String, dynamic> json) {
    var rawPolygon = json['geofence_polygon'];
    List<List<double>> poly = [];
    if (rawPolygon is List) {
      poly = rawPolygon.map((item) => (item as List).map((v) => (v as num).toDouble()).toList()).toList();
    } else if (rawPolygon is String) {
      var decoded = jsonDecode(rawPolygon);
      poly = (decoded as List).map((item) => (item as List).map((v) => (v as num).toDouble()).toList()).toList();
    }
    
    Map<String, double?> parsedPrices = {};
    if (json['prices'] != null) {
      json['prices'].forEach((k, v) {
        parsedPrices[k] = v != null ? (v as num).toDouble() : null;
      });
    }

    // Parse fuel_availability — default all to true if absent
    Map<String, bool> parsedAvailability = {
      for (final t in kFuelTypes) t: true,
    };
    if (json['fuel_availability'] != null && json['fuel_availability'] is Map) {
      (json['fuel_availability'] as Map).forEach((k, v) {
        parsedAvailability[k.toString()] = v == true || v == 1;
      });
    }

    return GasStation(
      id: json['id'],
      name: json['name'],
      branch: json['branch'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      geofencePolygon: poly,
      status: json['status'] ?? 'active',
      queueCount: json['queue_count'] ?? 0,
      waitTimeMinutes: (json['wait_time_minutes'] as num?)?.toDouble() ?? 0.0,
      prices: parsedPrices,
      fuelAvailability: parsedAvailability,
    );
  }
}

