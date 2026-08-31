import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gas_station.dart';
import '../models/vehicle_profile.dart';
import '../models/catalog_item.dart';

// API Base URL — 10.0.2.2 is the Android emulator alias for host localhost
String _defaultApiUrl() {
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api';
  return 'http://127.0.0.1:8000/api';
}

String apiBaseUrl = _defaultApiUrl();

Future<void> loadApiBaseUrl() async {
  final prefs = await SharedPreferences.getInstance();
  String stored = prefs.getString('api_base_url') ?? _defaultApiUrl();
  // Auto-migrate: if stored URL uses 127.0.0.1 but we're on Android emulator, fix it
  if (!kIsWeb && Platform.isAndroid && stored.contains('127.0.0.1')) {
    stored = stored.replaceAll('127.0.0.1', '10.0.2.2');
    await prefs.setString('api_base_url', stored);
  }
  apiBaseUrl = stored;
}

Future<void> saveApiBaseUrl(String newUrl) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('api_base_url', newUrl);
  apiBaseUrl = newUrl;
}

class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  String token = '';
  Map<String, dynamic>? currentUser;
  bool isSandboxMode = false;

  static List<List<double>> _generateFixedGeofence(double lat, double lng, {double radiusMeters = 15.0}) {
    const earthRadius = 6371000.0;
    List<List<double>> points = [];
    const numPoints = 16;
    for (int i = 0; i < numPoints; i++) {
      final angle = (i * 360.0 / numPoints) * pi / 180.0;
      final dLat = (radiusMeters / earthRadius) * cos(angle);
      final dLng = (radiusMeters / (earthRadius * cos(lat * pi / 180.0))) * sin(angle);
      points.add([
        lat + (dLat * 180.0 / pi),
        lng + (dLng * 180.0 / pi),
      ]);
    }
    return points;
  }

  // Local Sandbox Mocks (If backend server is offline)
  List<GasStation> mockStations = [
    GasStation(
      id: 'mock-petron-roxas',
      name: 'Petron',
      branch: 'Roxas Avenue',
      latitude: 7.07060000,
      longitude: 125.61520000,
      geofencePolygon: _generateFixedGeofence(7.07060000, 125.61520000),
      status: 'active',
      queueCount: 0,
      waitTimeMinutes: 0.0,
      prices: {
        'regular diesel': 75.0,
        'premium diesel': 81.0,
        'regular unleaded (91)': 71.0,
        'premium unleaded(95)': 78.0
      },
    ),
    GasStation(
      id: 'mock-shell-jp',
      name: 'Shell',
      branch: 'JP Laurel Ave',
      latitude: 7.08740000,
      longitude: 125.61670000,
      geofencePolygon: _generateFixedGeofence(7.08740000, 125.61670000),
      status: 'active',
      queueCount: 3,
      waitTimeMinutes: 9.0,
      prices: {
        'regular diesel': 74.5,
        'premium diesel': 80.5,
        'regular unleaded (91)': 68.5,
        'premium unleaded(95)': 75.0
      },
    ),
    GasStation(
      id: 'mock-caltex-quirino',
      name: 'Caltex',
      branch: 'Quirino Ave',
      latitude: 7.06550000,
      longitude: 125.60800000,
      geofencePolygon: _generateFixedGeofence(7.06550000, 125.60800000),
      status: 'active',
      queueCount: 1,
      waitTimeMinutes: 3.0,
      prices: {
        'regular diesel': 72.0,
        'premium diesel': 78.0,
        'regular unleaded (91)': 70.0,
        'premium unleaded(95)': 77.0
      },
    ),
  ];

  List<CatalogItem> mockCatalog = [
    CatalogItem(id: 'c1', make: 'Toyota', model: 'Vios', year: 2022, displacement: '1.3L', fuelType: 'unleaded', defaultEfficiency: 14.5, defaultIdlingRate: 1.00),
    CatalogItem(id: 'c2', make: 'Mitsubishi', model: 'Mirage', year: 2021, displacement: '1.2L', fuelType: 'unleaded', defaultEfficiency: 16.2, defaultIdlingRate: 0.80),
    CatalogItem(id: 'c3', make: 'Honda', model: 'Civic', year: 2023, displacement: '1.5T', fuelType: 'unleaded', defaultEfficiency: 12.8, defaultIdlingRate: 1.20),
    CatalogItem(id: 'c4', make: 'Isuzu', model: 'D-Max', year: 2020, displacement: '3.0L', fuelType: 'diesel', defaultEfficiency: 11.2, defaultIdlingRate: 1.80),
    CatalogItem(id: 'c5', make: 'Toyota', model: 'Fortuner', year: 2022, displacement: '2.8L', fuelType: 'diesel', defaultEfficiency: 10.5, defaultIdlingRate: 1.80),
  ];

  VehicleProfile? mockProfile = VehicleProfile(id: 'p1', catalogId: 'c1', vehicleType: 'Sedan', fuelEfficiency: 14.5, idlingRate: 1.00);

  Map<String, String> getHeaders() {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // Distance helper (Haversine)
  double getHaversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  // Polygon check
  bool isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
    if (polygon.isEmpty) return false;
    bool inside = false;
    int numPoints = polygon.length;
    for (int i = 0, j = numPoints - 1; i < numPoints; j = i++) {
      double latI = polygon[i][0];
      double lngI = polygon[i][1];
      double latJ = polygon[j][0];
      double lngJ = polygon[j][1];

      bool intersect = ((lngI > lng) != (lngJ > lng)) &&
          (lat < (latJ - latI) * (lng - lngI) / (lngJ - lngI) + latI);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
