import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../models/gas_station.dart';
import '../models/vehicle_profile.dart';
import '../models/catalog_item.dart';
import '../models/route_step.dart';
import '../services/api_service.dart';
import '../services/routing_service.dart';
import '../services/ocr_service.dart';
import '../widgets/badge_widget.dart';
import 'auth_gate.dart';
import 'location_explorer_screen.dart';
import 'leaderboard_screen.dart';

class MotoristDashboard extends StatefulWidget {
  const MotoristDashboard({super.key});

  @override
  State<MotoristDashboard> createState() => _MotoristDashboardState();
}

class _MotoristDashboardState extends State<MotoristDashboard> with WidgetsBindingObserver {
  int _currentIndex = 0;
  
  // Draggable Motorist mock coordinates in Davao City
  double motoristLat = 7.0725;
  double motoristLng = 125.6120;
  
  List<GasStation> stations = [];
  List<CatalogItem> catalog = [];
  VehicleProfile? vehicle;
  
  bool _isLoading = false;
  String fuelType = 'regular unleaded (91)';
  double liters = 30.0;
  String purchaseMode = 'liters'; // 'liters' or 'budget'
  double budget = 1000.0;

  // Two-factor motorist routing preferences
  String preferredBrand = 'All';
  String priceSensitivity = 'Medium';

  // Watchlist favorites
  Set<String> watchlistStationIds = {};
  File? ocrPhotoFile;
  OcrScanResult? ocrScanResult;
  bool _isOcrScanning = false;
  
  Map<String, dynamic> routingData = {};
  GoogleMapController? _googleMapController;
  BitmapDescriptor? _carMarkerIcon;

  Future<void> _loadCarMarker() async {
    try {
      final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(pictureRecorder);
      const double size = 120.0;
      final center = const Offset(size / 2, size / 2);

      // Outer soft aura glow
      final glowPaint = Paint()
        ..color = const Color(0xFF00FFCC).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, 44, glowPaint);

      // Deep dark sleek base circle
      final basePaint = Paint()..color = const Color(0xFF0F172A);
      canvas.drawCircle(center, 36, basePaint);

      // Vibrant emerald ring border
      final ringPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5;
      canvas.drawCircle(center, 36, ringPaint);

      // Sharp Navigation Arrow / Chevron pointing straight UP
      final arrowPath = Path()
        ..moveTo(size / 2, size / 2 - 24) // Tip
        ..lineTo(size / 2 + 18, size / 2 + 18) // Bottom right wing
        ..lineTo(size / 2, size / 2 + 8) // Recessed notch
        ..lineTo(size / 2 - 18, size / 2 + 18) // Bottom left wing
        ..close();

      final arrowPaint = Paint()
        ..color = const Color(0xFF00FFCC)
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);

      final picture = pictureRecorder.endRecording();
      final img = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final icon = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
        if (mounted) {
          setState(() {
            _carMarkerIcon = icon;
          });
        }
      }
    } catch (e) {
      debugPrint('Error generating car marker: $e');
    }
  }

  final _vehicleTypeController = TextEditingController();
  final _vehicleEfficiencyController = TextEditingController();
  final _vehicleIdlingRateController = TextEditingController();
  final _litersController = TextEditingController(text: '30');
  final _budgetController = TextEditingController(text: '1000');
  final _report91Controller = TextEditingController();
  final _report95Controller = TextEditingController();
  final _reportRegDslController = TextEditingController();
  final _reportPremDslController = TextEditingController();

  StreamSubscription<Position>? _positionStreamSubscription;
  String? _selectedCatalogId;
  bool _wasInsideGeofence = false;
  DateTime? _lastTelemetryPing;

  void _moveCamera(double lat, double lng, {double zoom = 18.5, double bearing = 0.0, double tilt = 60.0}) {
    if (_googleMapController != null) {
      _googleMapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: zoom,
            bearing: bearing,
            tilt: tilt,
          ),
        ),
      );
    }
  }

  IconData _getManeuverIcon(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('left')) {
      if (lower.contains('slight')) return Icons.turn_slight_left;
      if (lower.contains('sharp')) return Icons.turn_sharp_left;
      return Icons.turn_left;
    }
    if (lower.contains('right')) {
      if (lower.contains('slight')) return Icons.turn_slight_right;
      if (lower.contains('sharp')) return Icons.turn_sharp_right;
      return Icons.turn_right;
    }
    if (lower.contains('roundabout') || lower.contains('rotary')) return Icons.roundabout_left;
    if (lower.contains('arrive') || lower.contains('destination') || lower.contains('arrived')) return Icons.flag;
    return Icons.straight;
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * pi / 180.0;
    double lng1 = start.longitude * pi / 180.0;
    double lat2 = end.latitude * pi / 180.0;
    double lng2 = end.longitude * pi / 180.0;

    double dLon = lng2 - lng1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    double radians = atan2(y, x);
    double degrees = radians * 180.0 / pi;
    return (degrees + 360.0) % 360.0;
  }

  Future<void> _selectStationAndFetchRoute(GasStation station) async {
    setState(() {
      selectedStation = station;
    });
    await _fetchRoadRoute(station.latitude, station.longitude);
  }

  // Navigation Guidance State
  bool isNavigating = false;
  bool _autoFollowCamera = true;
  double _navTilt = 60.0; // 60.0 for 3D Perspective, 0.0 for 2D Overhead
  bool _isMuted = false;
  double currentBearing = 0.0;
  bool _showAllPrices = false;
  String? _selectedReportStationId;
  GasStation? navigationTarget;
  GasStation? selectedStation;
  double remainingDistance = 0.0;
  String guidanceText = 'Proceed toward station';
  List<LatLng> navigationRoutePoints = [];
  List<RouteStep> navigationSteps = []; // Parsed OSRM steps with coordinates
  List<String> navigationInstructions = [];
  int currentInstructionIndex = 0;
  String _lastSpokenInstruction = '';

  // TTS engine for audio guidance
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _speakInstruction(String text) async {
    if (_isMuted || text == _lastSpokenInstruction) return;
    _lastSpokenInstruction = text;
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.52);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
  }

  // Fetch actual driving route from OSRM
  Future<void> _fetchRoadRoute(double targetLat, double targetLng) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '$motoristLng,$motoristLat;$targetLng,$targetLat'
          '?overview=full&geometries=geojson&steps=true');
      
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final coords = route['geometry']['coordinates'] as List;
          
          List<LatLng> points = coords.map((c) => LatLng(
            (c[1] as num).toDouble(),
            (c[0] as num).toDouble()
          )).toList();

          List<String> instructions = [];
          List<RouteStep> parsedSteps = [];
          if (route['legs'] != null && route['legs'].isNotEmpty) {
            final rawSteps = route['legs'][0]['steps'] as List;
            for (var step in rawSteps) {
              final maneuver = step['maneuver'];
              if (maneuver != null) {
                final loc = maneuver['location'] as List;
                final instr = maneuver['instruction'] as String? ??
                    _osrmManeuverToText(maneuver);
                instructions.add(instr);
                parsedSteps.add(RouteStep(
                  instruction: instr,
                  latitude: (loc[1] as num).toDouble(),
                  longitude: (loc[0] as num).toDouble(),
                ));
              }
            }
          }

          if (mounted) {
            setState(() {
              navigationRoutePoints = points;
              navigationInstructions = instructions;
              navigationSteps = parsedSteps;
              currentInstructionIndex = 0;
              if (instructions.isNotEmpty) {
                guidanceText = instructions[0];
              }
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('OSRM Routing error, falling back to straight line: $e');
    }

    // Fallback: straight line
    if (mounted) {
      setState(() {
        navigationRoutePoints = [
          LatLng(motoristLat, motoristLng),
          LatLng(targetLat, targetLng),
        ];
        navigationInstructions = ['Proceed toward gas station (Offline Mode)'];
        navigationSteps = [
          RouteStep(
            instruction: 'Proceed toward gas station',
            latitude: targetLat,
            longitude: targetLng,
          )
        ];
        currentInstructionIndex = 0;
        guidanceText = 'Proceed toward gas station (Offline Mode)';
      });
    }
  }

  // Converts OSRM maneuver object to a human-readable instruction
  String _osrmManeuverToText(Map<dynamic, dynamic> maneuver) {
    final type = maneuver['type'] as String? ?? 'straight';
    final modifier = maneuver['modifier'] as String? ?? '';
    switch (type) {
      case 'turn':
        if (modifier.contains('left')) return 'Turn left';
        if (modifier.contains('right')) return 'Turn right';
        return 'Continue straight';
      case 'new name':
        return 'Continue on new road';
      case 'depart': return 'Start route – proceed toward destination';
      case 'arrive': return 'You have arrived';
      case 'merge': return 'Merge ${modifier.isNotEmpty ? modifier : "ahead"}';
      case 'ramp': return 'Take the ramp ${modifier.isNotEmpty ? modifier : ""}';
      case 'on ramp': return 'Take the on ramp';
      case 'off ramp': return 'Take the off ramp';
      case 'fork': return 'Keep ${modifier.isNotEmpty ? modifier : "straight"} at the fork';
      case 'roundabout': return 'Enter the roundabout';
      case 'rotary': return 'Enter the rotary';
      case 'roundabout turn': return 'Exit the roundabout';
      default: return 'Continue straight';
    }
  }

  // Tracks last position where route was re-fetched — throttles HTTP calls to every 50m
  double _lastRouteFetchLat = 0;
  double _lastRouteFetchLng = 0;

  // Helper method for motorist location updates
  Future<void> _updateLocation(double lat, double lng, {double speed = 35.0}) async {
    // --- single merged setState for position + nav data ---
    double dist = 0;
    bool arrived = false;
    bool insideFence = false;

    if (isNavigating && navigationTarget != null) {
      dist = AppState().getHaversineDistance(
        lat, lng,
        navigationTarget!.latitude,
        navigationTarget!.longitude,
      );
      insideFence = AppState().isPointInPolygon(lat, lng, navigationTarget!.geofencePolygon);
      arrived = dist < 0.015 || insideFence;
    }

    if (!mounted) return;
    setState(() {
      motoristLat = lat;
      motoristLng = lng;
      if (isNavigating && navigationTarget != null) {
        remainingDistance = dist;
        if (arrived) {
          isNavigating = false;
          guidanceText = 'Arrived at destination';
        }
      }
    });

    if (arrived && navigationTarget != null) {
      _showArrivalDialog(navigationTarget!);
      if (mounted) {
        setState(() {
          navigationTarget = null;
          navigationRoutePoints = [];
          navigationInstructions = [];
        });
      }
      return;
    }

    if (isNavigating && navigationTarget != null) {
      // Throttle route re-fetch: only update route when moved > 50m from last fetch
      final movedSinceLastFetch = AppState().getHaversineDistance(
        lat, lng, _lastRouteFetchLat, _lastRouteFetchLng) * 1000; // metres
      if (_lastRouteFetchLat == 0 || movedSinceLastFetch > 50) {
        _lastRouteFetchLat = lat;
        _lastRouteFetchLng = lng;
        await _fetchRoadRoute(navigationTarget!.latitude, navigationTarget!.longitude);
      }

        // Proximity-based step tracking
        String newGuidance = guidanceText;
        if (remainingDistance < 0.05) {
          newGuidance = 'Arriving – slow down and enter the gas station';
        } else if (navigationSteps.isNotEmpty) {
          // Find nearest step within 30m
          for (int i = 0; i < navigationSteps.length; i++) {
            final step = navigationSteps[i];
            final stepDist = AppState().getHaversineDistance(lat, lng, step.latitude, step.longitude);
            if (stepDist < 0.030) {
              // Within 30m of this step's maneuver point
              if (i != currentInstructionIndex) {
                setState(() => currentInstructionIndex = i);
              }
              newGuidance = step.instruction;
              break;
            }
          }
          // Look ahead: announce upcoming turn if within 150m
          if (currentInstructionIndex + 1 < navigationSteps.length) {
            final nextStep = navigationSteps[currentInstructionIndex + 1];
            final nextDist = AppState().getHaversineDistance(lat, lng, nextStep.latitude, nextStep.longitude);
            if (nextDist < 0.150 && nextDist > 0.030) {
              newGuidance = 'In ${(nextDist * 1000).toInt()}m – ${nextStep.instruction}';
            }
          }
        } else if (navigationInstructions.isNotEmpty) {
          newGuidance = navigationInstructions[0];
        }

        if (newGuidance != guidanceText) {
          setState(() => guidanceText = newGuidance);
          await _speakInstruction(newGuidance);
        }
      }

    // Auto-center map if navigating
    if (isNavigating) {
      double bearing = currentBearing;
      if (navigationRoutePoints.length >= 2) {
        LatLng nextPoint = navigationRoutePoints[1];
        for (int i = 1; i < navigationRoutePoints.length; i++) {
          double d = AppState().getHaversineDistance(
            lat,
            lng,
            navigationRoutePoints[i].latitude,
            navigationRoutePoints[i].longitude,
          );
          if (d > 0.005) { // 5 meters
            nextPoint = navigationRoutePoints[i];
            break;
          }
        }
        bearing = _calculateBearing(LatLng(lat, lng), nextPoint);
        currentBearing = bearing;
      }
      if (_autoFollowCamera) {
        _moveCamera(lat, lng, zoom: 18.5, bearing: _navTilt > 0 ? bearing : 0.0, tilt: _navTilt);
      }
    }

    // Fire-and-forget (non-blocking). Throttled separately.
    unawaited(_fetchRoutingCalculations());
    unawaited(_pingLocation(lat, lng, speed));
  }

  void _showArrivalDialog(GasStation station) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D131F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Arrived!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text(
                    '${station.name} – ${station.branch}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.normal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You are now inside the station perimeter. Would you like to report current fuel prices?',
              style: TextStyle(fontSize: 14, color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reporting prices helps other motorists find the best deals nearby.',
                      style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 0);
            },
            child: const Text('Stay on Map', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _currentIndex = 2); // Navigate to Price Reporting tab
            },
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('Report Prices', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }


  String? getVehicleFuelType() {
    if (vehicle == null || vehicle!.catalogId == null) return null;
    try {
      final catalogItem = catalog.firstWhere((c) => c.id == vehicle!.catalogId);
      return catalogItem.fuelType; // unleaded or diesel
    } catch (_) {
      return null;
    }
  }

  void _resetFuelTypeIfIncompatible() {
    final vFuelType = getVehicleFuelType();
    if (vFuelType == 'unleaded') {
      if (fuelType != 'regular unleaded (91)' && fuelType != 'premium unleaded(95)') {
        fuelType = 'regular unleaded (91)';
      }
    } else if (vFuelType == 'diesel') {
      if (fuelType != 'regular diesel' && fuelType != 'premium diesel') {
        fuelType = 'regular diesel';
      }
    }
  }

  List<DropdownMenuItem<String>> _buildFuelDropdownItems() {
    final vFuelType = getVehicleFuelType();
    if (vFuelType == 'unleaded') {
      return const [
        DropdownMenuItem(value: 'regular unleaded (91)', child: Text('Regular Unleaded (91)')),
        DropdownMenuItem(value: 'premium unleaded(95)', child: Text('Premium Unleaded (95)')),
      ];
    } else if (vFuelType == 'diesel') {
      return const [
        DropdownMenuItem(value: 'regular diesel', child: Text('Regular Diesel')),
        DropdownMenuItem(value: 'premium diesel', child: Text('Premium Diesel')),
      ];
    } else {
      return const [
        DropdownMenuItem(value: 'regular unleaded (91)', child: Text('Regular Unleaded (91)')),
        DropdownMenuItem(value: 'premium unleaded(95)', child: Text('Premium Unleaded (95)')),
        DropdownMenuItem(value: 'regular diesel', child: Text('Regular Diesel')),
        DropdownMenuItem(value: 'premium diesel', child: Text('Premium Diesel')),
      ];
    }
  }

  void _showSavingsBreakdownDialog(Map<String, dynamic> data) {
    final double netSavings = (data['net_savings_php'] as num).toDouble();
    final double grossSavings = (data['gross_savings_php'] as num).toDouble();
    final double travelCost = (data['travel_cost_php'] as num).toDouble();
    final double targetPrice = (data['price'] as num).toDouble();
    final double basePrice = (routingData['baseline_price'] as num?)?.toDouble() ?? targetPrice;
    final double litersPurchased = (data['liters_purchased'] as num).toDouble();
    final double rawDist = (data['raw_distance_km'] as num).toDouble();
    final double eff = (routingData['fuel_efficiency_kml'] as num?)?.toDouble() ?? 12.5;
    final double idlingRate = vehicle?.idlingRate ?? 1.2;
    
    double sensitivityFactor = 1.0;
    if (priceSensitivity.toLowerCase() == 'high') sensitivityFactor = 0.5;
    else if (priceSensitivity.toLowerCase() == 'low') sensitivityFactor = 2.0;

    final double trafficFactor = routingData['traffic_factor'] != null ? (routingData['traffic_factor'] as num).toDouble() : 1.2;
    final double effectiveDist = rawDist * 1.3 * trafficFactor;
    final double fuelDriving = effectiveDist / eff;
    final double queueMins = data['wait_time_minutes'] != null ? (data['wait_time_minutes'] as num).toDouble() : (data['queue_count'] * 3.0);
    final double fuelIdling = (queueMins / 60.0) * idlingRate;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calculate_outlined, color: Theme.of(context).primaryColor),
            const SizedBox(width: 10),
            const Text('Savings Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${data['name']} \u2013 ${data['branch']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Divider(height: 16),
              
              const Text('1. Gross Fuel Savings:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                'Liters × (Baseline Price - Target Price)\n'
                '• Baseline Price: ₱${basePrice.toStringAsFixed(2)}/L\n'
                '• Target Price: ₱${targetPrice.toStringAsFixed(2)}/L\n'
                '• Volume: ${litersPurchased.toStringAsFixed(2)} L\n'
                '• Math: ${litersPurchased.toStringAsFixed(2)} L × (₱${basePrice.toStringAsFixed(2)} - ₱${targetPrice.toStringAsFixed(2)})\n'
                '➡ Gross Savings: ₱${grossSavings.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[800], height: 1.4),
              ),
              const SizedBox(height: 15),

              const Text('2. Travel Detour Cost (Target):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '(Driving Fuel + Idling Fuel) × Price × Sensitivity\n'
                '• Est. Distance (w/ Traffic): ${effectiveDist.toStringAsFixed(2)} km\n'
                '• Driving Fuel: ${effectiveDist.toStringAsFixed(2)} km / ${eff.toStringAsFixed(1)} km/L = ${fuelDriving.toStringAsFixed(2)} L\n'
                '• Waiting Time: ${queueMins.toStringAsFixed(0)} mins (${data['queue_count']} cars)\n'
                '• Idling Fuel: (${queueMins.toStringAsFixed(0)}m / 60) × ${idlingRate.toStringAsFixed(1)} L/h = ${fuelIdling.toStringAsFixed(2)} L\n'
                '• Total Travel Fuel: ${(fuelDriving + fuelIdling).toStringAsFixed(2)} L\n'
                '• Sensitivity: ${priceSensitivity} (${sensitivityFactor}x)\n'
                '➡ Detour Cost: ₱${travelCost.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[800], height: 1.4),
              ),
              const SizedBox(height: 15),

              const Text('3. Relative Net Detour Savings:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                'Gross Savings - (Target Detour - Baseline Detour)\n'
                'Net Savings accounts for the extra travel fuel to target station relative to the closest baseline station:\n'
                '➡ Net Savings: ₱${netSavings.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[800], height: 1.4),
              ),
              const SizedBox(height: 15),
              
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: netSavings >= 0 ? const Color(0xFF10B981).withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      netSavings >= 0 ? Icons.check_circle_outline : Icons.error_outline,
                      color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        netSavings >= 0
                            ? 'Visiting this station saves you a net of ₱${netSavings.toStringAsFixed(2)} after detour driving & idling fuel costs.'
                            : 'Not recommended. Detour costs exceed fuel savings by ₱${netSavings.abs().toStringAsFixed(2)}.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: netSavings >= 0 ? Colors.green[950] : Colors.red[950],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPricesWidget(Map<String, dynamic> data) {
    final pricesMap = data['prices'] ?? {};
    final p91 = pricesMap['regular unleaded (91)'];
    final p95 = pricesMap['premium unleaded(95)'];
    final pRegDsl = pricesMap['regular diesel'];
    final pPremDsl = pricesMap['premium diesel'];

    final vehicleFuel = getVehicleFuelType();
    
    bool showUnleaded = true;
    bool showDiesel = true;
    
    if (vehicleFuel != null && !_showAllPrices) {
      if (vehicleFuel == 'unleaded') {
        showDiesel = false;
      } else if (vehicleFuel == 'diesel') {
        showUnleaded = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showUnleaded) ...[
          Row(
            children: [
              Expanded(child: _buildPriceBadge('Unleaded 91', p91, Colors.green[800]!)),
              const SizedBox(width: 8),
              Expanded(child: _buildPriceBadge('Premium Unleaded 95', p95, Colors.blue[900]!)),
            ],
          ),
        ],
        if (showUnleaded && showDiesel) const SizedBox(height: 8),
        if (showDiesel) ...[
          Row(
            children: [
              Expanded(child: _buildPriceBadge('Regular Diesel', pRegDsl, Colors.orange[900]!)),
              const SizedBox(width: 8),
              Expanded(child: _buildPriceBadge('Premium Diesel', pPremDsl, Colors.purple[800]!)),
            ],
          ),
        ],
        if (vehicleFuel != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () {
                setState(() {
                  _showAllPrices = !_showAllPrices;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(
                  _showAllPrices ? 'Show only relevant fuel' : 'Show all fuel variants',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceBadge(String name, dynamic priceVal, Color accentColor) {
    final priceStr = priceVal != null ? '₱${(priceVal as num).toStringAsFixed(2)}' : 'N/A';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name, 
            style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            priceStr, 
            style: TextStyle(fontSize: 14, color: accentColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleWatchlist(String stationId) async {
    final isFav = watchlistStationIds.contains(stationId);
    setState(() {
      if (isFav) {
        watchlistStationIds.remove(stationId);
      } else {
        watchlistStationIds.add(stationId);
      }
    });

    if (AppState().isSandboxMode) return;

    try {
      if (isFav) {
        await http.delete(
          Uri.parse('$apiBaseUrl/watchlist/$stationId'),
          headers: AppState().getHeaders(),
        );
      } else {
        await http.post(
          Uri.parse('$apiBaseUrl/watchlist'),
          headers: AppState().getHeaders(),
          body: jsonEncode({'station_id': stationId}),
        );
      }
    } catch (e) {
      print('Toggle watchlist error: $e');
    }
  }

  Widget _buildWatchlistView() {
    final favoritedStations = stations.where((s) => watchlistStationIds.contains(s.id)).toList();

    return favoritedStations.isEmpty
        ? Center(
            child: Text(
              'Your Watchlist is empty.\nTap the heart icon on any station to monitor it remotely.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500),
            ),
          )
        : ListView.builder(
            itemCount: favoritedStations.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final station = favoritedStations[index];
              return Card(
                elevation: 2,
                color: Theme.of(context).cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${station.name} – ${station.branch}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.favorite, color: Colors.red),
                            onPressed: () => _toggleWatchlist(station.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'RETAIL PRICE GRID', 
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      _buildPricesWidget({'prices': station.prices}),
                      const SizedBox(height: 10),
                      Text(
                        'As of: ${DateTime.now().toLocal().toString().substring(0, 16)}',
                        style: TextStyle(fontSize: 10, color: Colors.grey[700], fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCarMarker();
    _litersController.text = liters.toStringAsFixed(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWithLocation();
    });
  }

  Future<void> _initWithLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Please enable them.')),
          );
        }
        await _fetchData();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        await _fetchData();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('GPS timeout');
      });

      motoristLat = position.latitude;
      motoristLng = position.longitude;

      await _fetchData();

      _startLocationTracking();
      _moveCamera(motoristLat, motoristLng, zoom: 14.5, bearing: 0.0, tilt: 0.0);
    } catch (e) {
      print('Init location error: $e');
      await _fetchData();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startLocationTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 metres for smooth car navigation tracking
      ),
    ).listen((Position position) {
      _updateLocation(position.latitude, position.longitude, speed: position.speed);
      if (isNavigating) {
        double bearing = currentBearing;
        if (position.heading > 0) {
          bearing = position.heading;
          currentBearing = bearing;
        } else if (navigationRoutePoints.length >= 2) {
          bearing = _calculateBearing(LatLng(position.latitude, position.longitude), navigationRoutePoints[1]);
          currentBearing = bearing;
        }
        if (_autoFollowCamera) {
          _moveCamera(position.latitude, position.longitude, zoom: 18.5, bearing: bearing, tilt: 60.0);
        }
      }
    }, onError: (e) {
      print('Location stream error: $e');
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _liveSyncTimer?.cancel();
    _vehicleTypeController.dispose();
    _vehicleEfficiencyController.dispose();
    _vehicleIdlingRateController.dispose();
    _litersController.dispose();
    _budgetController.dispose();
    _report91Controller.dispose();
    _report95Controller.dispose();
    _reportRegDslController.dispose();
    _reportPremDslController.dispose();
    _flutterTts.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Timer? _liveSyncTimer;

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted || AppState().isSandboxMode) return;
      try {
        final res = await http.get(Uri.parse('$apiBaseUrl/gas-stations/live'), headers: AppState().getHeaders());
        if (res.statusCode == 200) {
          final List updates = jsonDecode(res.body);
          if (!mounted) return;
          setState(() {
            for (var u in updates) {
              final sId = u['id'];
              final matches = stations.where((s) => s.id == sId);
              if (matches.isNotEmpty) {
                final match = matches.first;
                match.queueCount = u['queue_count'] ?? match.queueCount;
                match.waitTimeMinutes = (u['wait_time_minutes'] as num?)?.toDouble() ?? match.waitTimeMinutes;
                match.status = u['status'] ?? match.status;
                if (u['prices'] != null) {
                  (u['prices'] as Map).forEach((k, v) {
                    match.prices[k.toString()] = v != null ? (v as num).toDouble() : null;
                  });
                }
              }
            }
          });
          _computeSavingsLocally();
        }
      } catch (e) {
        debugPrint('Live sync error: $e');
      }
    });
  }

  bool _isMotoristInGeofence(GasStation station) {
    if (AppState().isSandboxMode) return true;
    final distKm = AppState().getHaversineDistance(
      motoristLat,
      motoristLng,
      station.latitude,
      station.longitude,
    );
    final isInsidePolygon = AppState().isPointInPolygon(
      motoristLat,
      motoristLng,
      station.geofencePolygon,
    );
    return distKm <= 0.15 || isInsidePolygon;
  }

  void _showGeofenceRestrictionDialog(GasStation station, String featureName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 24),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Geofence Restriction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To ensure data credibility, $featureName is restricted to motorists physically present at the station perimeter (~100m range).',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_off_rounded, color: Colors.amber.shade900, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your current GPS location is outside ${station.name} (${station.branch}).',
                      style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Understand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _showQueueReportDialog(GasStation station) {
    if (!_isMotoristInGeofence(station)) {
      _showGeofenceRestrictionDialog(station, 'station queue reporting');
      return;
    }

    int selectedQueue = station.queueCount;


    Widget buildQueueOption({
      required String label,
      required String vehicleCount,
      required String waitTime,
      required Color color,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))]
                  : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            child: Row(
              children: [
                // Modern Glow Dot Indicator
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: color.withOpacity(0.4), blurRadius: 4, spreadRadius: 1),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label ($vehicleCount)',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected ? Colors.black87 : Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Wait time: $waitTime',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle_rounded, color: color, size: 20),
              ],
            ),
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people_alt_rounded, color: Color(0xFF059669), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Report Station Queue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      '${station.name} (${station.branch})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select current waiting line condition:', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
              const SizedBox(height: 14),
              buildQueueOption(
                label: 'Clear / Low',
                vehicleCount: '0 – 1 cars',
                waitTime: '~0–3 mins',
                color: const Color(0xFF10B981),
                isSelected: selectedQueue <= 1,
                onTap: () => setDialogState(() => selectedQueue = 1),
              ),
              buildQueueOption(
                label: 'Moderate',
                vehicleCount: '2 – 4 cars',
                waitTime: '~6–12 mins',
                color: const Color(0xFFF59E0B),
                isSelected: selectedQueue >= 2 && selectedQueue <= 4,
                onTap: () => setDialogState(() => selectedQueue = 3),
              ),
              buildQueueOption(
                label: 'High',
                vehicleCount: '5 – 7 cars',
                waitTime: '~15–21 mins',
                color: const Color(0xFFF97316),
                isSelected: selectedQueue >= 5 && selectedQueue <= 7,
                onTap: () => setDialogState(() => selectedQueue = 6),
              ),
              buildQueueOption(
                label: 'Congested',
                vehicleCount: '8+ cars',
                waitTime: '~24+ mins',
                color: const Color(0xFFEF4444),
                isSelected: selectedQueue >= 8,
                onTap: () => setDialogState(() => selectedQueue = 9),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _submitQueueReport(station.id, selectedQueue);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Submit Queue Update', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _submitQueueReport(String stationId, int queueCount) async {
    final matches = stations.where((s) => s.id == stationId);
    if (matches.isNotEmpty) {
      final station = matches.first;
      setState(() {
        station.queueCount = queueCount;
        station.waitTimeMinutes = queueCount * 3.0;
      });
    }

    if (AppState().isSandboxMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Queue condition updated! +1 Trust Score ⭐'), backgroundColor: Colors.green),
        );
      }
      _computeSavingsLocally();
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/gas-stations/$stationId/queue'),
        headers: AppState().getHeaders(),
        body: jsonEncode({
          'queue_count': queueCount,
          'wait_time_minutes': queueCount * 3.0,
          'latitude': motoristLat,
          'longitude': motoristLng,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Queue condition submitted! +1 Trust Score ⭐'), backgroundColor: Colors.green),
          );
        }
        _fetchData();
      } else {
        final data = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Failed to update queue.'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      debugPrint('Queue report error: $e');
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });

    if (AppState().isSandboxMode) {
      stations = AppState().mockStations;
      catalog = AppState().mockCatalog;
      vehicle = AppState().mockProfile;
      _selectedCatalogId = vehicle?.catalogId;
      _vehicleTypeController.text = vehicle?.vehicleType ?? 'Sedan';
      _vehicleEfficiencyController.text = vehicle?.fuelEfficiency.toString() ?? '14.5';
      _vehicleIdlingRateController.text = vehicle?.idlingRate.toString() ?? '1.20';
      _resetFuelTypeIfIncompatible();
      _computeSavingsLocally();
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final results = await Future.wait([
        http.get(Uri.parse('$apiBaseUrl/gas-stations'), headers: AppState().getHeaders()),
        http.get(Uri.parse('$apiBaseUrl/vehicle-catalog'), headers: AppState().getHeaders()),
        http.get(Uri.parse('$apiBaseUrl/vehicle'), headers: AppState().getHeaders()),
        http.get(Uri.parse('$apiBaseUrl/watchlist'), headers: AppState().getHeaders()),
      ]).timeout(const Duration(seconds: 4));

      final stationsRes = results[0];
      final catalogRes = results[1];
      final profileRes = results[2];
      final watchlistRes = results[3];

      if (stationsRes.statusCode == 200) {
        final List parsed = jsonDecode(stationsRes.body);
        stations = parsed.map((x) => GasStation.fromJson(x)).toList();
      }

      if (catalogRes.statusCode == 200) {
        final List parsed = jsonDecode(catalogRes.body);
        catalog = parsed.map((x) => CatalogItem.fromJson(x)).toList();
      }

      if (profileRes.statusCode == 200) {
        vehicle = VehicleProfile.fromJson(jsonDecode(profileRes.body));
        _selectedCatalogId = vehicle?.catalogId;
        _vehicleTypeController.text = vehicle?.vehicleType ?? 'Sedan';
        _vehicleEfficiencyController.text = vehicle?.fuelEfficiency.toString() ?? '14.5';
        _vehicleIdlingRateController.text = vehicle?.idlingRate.toString() ?? '1.20';
      }

      if (watchlistRes.statusCode == 200) {
        final List parsed = jsonDecode(watchlistRes.body);
        watchlistStationIds = parsed.map<String>((x) => x['id'].toString()).toSet();
      }

      _resetFuelTypeIfIncompatible();

      await _fetchRoutingCalculations(forceRefresh: true);
      _startLiveSync();
    } catch (e) {
      print('Network error fetching: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backend server unreachable at $apiBaseUrl. Check connection.'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isFetchingCalculations = false;
  DateTime? _lastRoutingCalc;

  Future<void> _fetchRoutingCalculations({bool forceRefresh = false}) async {
    if (_isFetchingCalculations) return;
    final now = DateTime.now();
    if (!forceRefresh && _lastRoutingCalc != null &&
        now.difference(_lastRoutingCalc!) < const Duration(seconds: 8)) {
      return;
    }
    _isFetchingCalculations = true;
    _lastRoutingCalc = now;

    if (AppState().isSandboxMode) {
      _computeSavingsLocally();
      _isFetchingCalculations = false;
      return;
    }

    try {
      final url = Uri.parse('$apiBaseUrl/gas-stations/routing?'
          'latitude=$motoristLat&'
          'longitude=$motoristLng&'
          'fuel_type=$fuelType&'
          'purchase_mode=$purchaseMode&'
          'liters=$liters&'
          'budget=$budget&'
          'preferred_brand=$preferredBrand&'
          'price_sensitivity=${priceSensitivity.toLowerCase()}');
      
      final res = await http.get(url, headers: AppState().getHeaders()).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        setState(() {
          routingData = jsonDecode(res.body);
        });
        _autoSelectOptimalStation();
      } else {
        _computeSavingsLocally();
      }
    } catch (e) {
      print('Routing API error $e');
      _computeSavingsLocally();
    } finally {
      _isFetchingCalculations = false;
    }
  }

  void _computeSavingsLocally() {
    final result = RoutingService.computeOptimalRoutes(
      motoristLat: motoristLat,
      motoristLng: motoristLng,
      fuelType: fuelType,
      purchaseMode: purchaseMode,
      liters: liters,
      budget: budget,
      vehicle: vehicle,
      stations: stations,
      preferredBrand: preferredBrand,
      priceSensitivity: priceSensitivity.toLowerCase(),
    );
    if (result != null) {
      setState(() {
        routingData = result;
      });
      _autoSelectOptimalStation();
    }
  }

  void _autoSelectOptimalStation() {
    List stationsList = routingData['stations'] ?? [];
    if (stationsList.isNotEmpty) {
      final bestStationData = stationsList.first;
      final bestStationId = bestStationData['station_id'];
      try {
        final bestStation = stations.firstWhere((s) => s.id == bestStationId);
        if (selectedStation == null || !isNavigating) {
          _selectStationAndFetchRoute(bestStation);
        }
      } catch (e) {
        print('Error auto-selecting optimal station: $e');
      }
    }
  }

  Future<bool> _reportAllPrices(String stationId, Map<String, double> fuelPrices, {File? photoFile}) async {
    final station = stations.firstWhere((s) => s.id == stationId);
    final isInsideFence = _isMotoristInGeofence(station);

    if (AppState().isSandboxMode) {
      if (isInsideFence) {
        setState(() {
          fuelPrices.forEach((type, price) {
            station.prices[type] = price;
          });
        });
        _computeSavingsLocally();
      }
      return isInsideFence;
    }

    bool anomalyFlagged = false;
    bool allInsideFence = true;

    final uri = Uri.parse('$apiBaseUrl/gas-stations/$stationId/prices');
    final headers = AppState().getHeaders();

    http.Response res;
    if (photoFile != null) {
      // Single upload: only 1 photo is sent for all fuel variants together
      final request = http.MultipartRequest('POST', uri);
      request.headers.addAll(headers);
      request.fields['prices'] = jsonEncode(fuelPrices);
      request.fields['latitude'] = motoristLat.toString();
      request.fields['longitude'] = motoristLng.toString();
      request.files.add(await http.MultipartFile.fromPath(
        'photo',
        photoFile.path,
        filename: photoFile.path.split(Platform.pathSeparator).last,
      ));
      final streamedRes = await request.send();
      res = await http.Response.fromStream(streamedRes);
    } else {
      // Single JSON POST when no photo
      res = await http.post(
        uri,
        headers: headers,
        body: jsonEncode({
          'prices': fuelPrices,
          'latitude': motoristLat,
          'longitude': motoristLng,
        }),
      );
    }

    final data = jsonDecode(res.body);
    if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 202) {
      if (data['anomaly_flagged'] == true) anomalyFlagged = true;
      if (data['is_inside_geofence'] == false) allInsideFence = false;
      // Photo submission held for admin review — not an error, just pending
      if (data['pending_review'] == true) {
        await _fetchData();
        throw Exception(
          '📸 Photo submitted! An admin will review your image and approve the prices before they go live.'
        );
      }
    } else {
      throw Exception(data['message'] ?? 'Failed to report prices');
    }

    await _fetchData();
    if (anomalyFlagged) {
      throw Exception('Warning: One or more reported prices were flagged for admin audit review.');
    }

    return isInsideFence && allInsideFence;
  }

  Future<void> _saveVehicleProfile(String? catId, String type, double efficiency, {double idlingRate = 1.20}) async {
    if (AppState().isSandboxMode) {
      setState(() {
        vehicle = VehicleProfile(id: 'mock-p', catalogId: catId, vehicleType: type, fuelEfficiency: efficiency, idlingRate: idlingRate);
        AppState().mockProfile = vehicle;
        _selectedCatalogId = catId;
        _vehicleTypeController.text = type;
        _vehicleEfficiencyController.text = efficiency.toString();
        _vehicleIdlingRateController.text = idlingRate.toString();
        _resetFuelTypeIfIncompatible();
      });
      _computeSavingsLocally();
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/vehicle'),
        headers: AppState().getHeaders(),
        body: jsonEncode({
          'catalog_id': catId,
          'vehicle_type': type,
          'fuel_efficiency': efficiency,
          'idling_rate': idlingRate,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        setState(() {
          vehicle = VehicleProfile.fromJson(jsonDecode(res.body));
          _selectedCatalogId = vehicle?.catalogId;
          _vehicleTypeController.text = vehicle?.vehicleType ?? '';
          _vehicleEfficiencyController.text = vehicle?.fuelEfficiency.toString() ?? '';
          _vehicleIdlingRateController.text = vehicle?.idlingRate.toString() ?? '1.20';
          _resetFuelTypeIfIncompatible();
        });
        _fetchRoutingCalculations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update vehicle profile on server: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pingLocation(double lat, double lng, double speed) async {
    bool isInsideAny = false;
    for (var s in stations) {
      if (AppState().isPointInPolygon(lat, lng, s.geofencePolygon)) {
        isInsideAny = true;
        break;
      }
    }

    if (!isInsideAny) {
      if (_wasInsideGeofence) {
        _wasInsideGeofence = false;
        try {
          await http.post(
            Uri.parse('$apiBaseUrl/telemetry'),
            headers: AppState().getHeaders(),
            body: jsonEncode({'latitude': lat, 'longitude': lng, 'velocity': 50.0}),
          );
        } catch (_) {}
      }
      return;
    }

    _wasInsideGeofence = true;
    final now = DateTime.now();
    if (_lastTelemetryPing != null &&
        now.difference(_lastTelemetryPing!) < const Duration(seconds: 15)) {
      return;
    }
    _lastTelemetryPing = now;

    try {
      await http.post(
        Uri.parse('$apiBaseUrl/telemetry'),
        headers: AppState().getHeaders(),
        body: jsonEncode({
          'latitude': lat,
          'longitude': lng,
          'velocity': speed,
        }),
      );
      unawaited(_fetchRoutingCalculations());
    } catch (e) {
      print('Telemetry ping error $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildMapView(),
      _buildWatchlistView(),
      _buildProfileView(),
      _buildReportView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/logo.png',
          height: 26,
          errorBuilder: (context, error, stackTrace) => const Text('RoutePump', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined, color: Color(0xFFF59E0B)),
            tooltip: 'Leaderboard & Trust Score',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              AppState().token = '';
              AppState().currentUser = null;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthGate()));
            },
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey[600],
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Map & Route'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'Watchlist'),
          BottomNavigationBarItem(icon: Icon(Icons.directions_car_filled_outlined), label: 'My Vehicle'),
          BottomNavigationBarItem(icon: Icon(Icons.add_location_alt_outlined), label: 'Report Price'),
        ],
      ),
    );
  }

  Set<Marker> _buildNavigationMarkers() {
    final Set<Marker> markerSet = {};

    // 1. Motorist Vehicle / Navigation Chevron Marker (Course-Up, Flat 3D tilted)
    markerSet.add(
      Marker(
        markerId: const MarkerId('nav_motorist'),
        position: LatLng(motoristLat, motoristLng),
        rotation: currentBearing,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        icon: _carMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: const InfoWindow(title: 'Your Vehicle'),
        zIndex: 3.0,
      ),
    );

    // 2. Destination Gas Station Target Marker
    if (navigationTarget != null) {
      markerSet.add(
        Marker(
          markerId: MarkerId('nav_station_${navigationTarget!.id}'),
          position: LatLng(navigationTarget!.latitude, navigationTarget!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '${navigationTarget!.name} – ${navigationTarget!.branch}',
            snippet: 'Queue: ${navigationTarget!.queueCount} cars | Wait: ${navigationTarget!.waitTimeMinutes.toInt()} mins',
          ),
          zIndex: 2.0,
        ),
      );
    }

    return markerSet;
  }

  Set<Polyline> _buildNavigationPolylines() {
    final Set<Polyline> polylineSet = {};

    if (navigationRoutePoints.isNotEmpty) {
      // 1. Dark high-contrast casing line underneath
      polylineSet.add(
        Polyline(
          polylineId: const PolylineId('nav_route_casing'),
          points: navigationRoutePoints,
          color: const Color(0xFF064E3B),
          width: 9,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 1,
        ),
      );

      // 2. Glowing vibrant neon navigation route line
      polylineSet.add(
        Polyline(
          polylineId: const PolylineId('nav_route_path'),
          points: navigationRoutePoints,
          color: const Color(0xFF00FFCC),
          width: 6,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          zIndex: 2,
        ),
      );
    }

    return polylineSet;
  }

  Widget _buildMapView() {
    List stationsList = routingData['stations'] ?? [];
    Map? optimalStation = stationsList.isNotEmpty ? stationsList.first : null;

    if (isNavigating && navigationTarget != null) {
      Map? targetData;
      try {
        targetData = stationsList.firstWhere((item) => item['station_id'] == navigationTarget!.id);
      } catch (_) {}

      return Stack(
        children: [
          // Native Hardware-Accelerated Google Map in 3D Car Navigation Mode (Course-Up, 60 deg Tilt)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(motoristLat, motoristLng),
              zoom: 18.5,
              bearing: currentBearing,
              tilt: 60.0,
            ),
            mapType: MapType.normal,
            onMapCreated: (controller) {
              _googleMapController = controller;
              controller.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: LatLng(motoristLat, motoristLng),
                    zoom: 18.5,
                    bearing: currentBearing,
                    tilt: 60.0,
                  ),
                ),
              );
            },
            onCameraMoveStarted: () {
              // If driver drags the map, decouple auto-follow
              if (_autoFollowCamera) {
                setState(() => _autoFollowCamera = false);
              }
            },
            markers: _buildNavigationMarkers(),
            polylines: _buildNavigationPolylines(),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            trafficEnabled: true,
            buildingsEnabled: true,
            mapToolbarEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
          ),

          // Top Turn-by-Turn Maneuver HUD Banner
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.95),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Icon(
                      _getManeuverIcon(guidanceText),
                      color: const Color(0xFF10B981),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guidanceText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              remainingDistance < 1.0
                                  ? '${(remainingDistance * 1000).toInt()} meters'
                                  : '${remainingDistance.toStringAsFixed(2)} km remaining',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '|   Est. ${(remainingDistance * 2.2).ceil()} mins',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Map Control Floating Button (Audio Mute/Unmute only - 3D and Satellite removed)
          Positioned(
            top: 110,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'mute_btn',
              backgroundColor: const Color(0xFF0F172A).withOpacity(0.9),
              foregroundColor: _isMuted ? Colors.redAccent : const Color(0xFF10B981),
              tooltip: _isMuted ? 'Unmute Audio Guidance' : 'Mute Audio Guidance',
              onPressed: () {
                setState(() {
                  _isMuted = !_isMuted;
                });
                if (_isMuted) {
                  _flutterTts.stop();
                }
              },
              child: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                size: 18,
              ),
            ),
          ),

          // Floating Recenter Camera Button (when motorist panned the map)
          if (!_autoFollowCamera)
            Positioned(
              bottom: 185,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _autoFollowCamera = true);
                    _moveCamera(
                      motoristLat,
                      motoristLng,
                      zoom: 18.5,
                      bearing: currentBearing,
                      tilt: 60.0,
                    );
                  },
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('RECENTER CAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 6,
                  ),
                ),
              ),
            ),

          // Bottom Target Station Details & End Navigation Card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${navigationTarget!.name} \u2013 ${navigationTarget!.branch}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Queue: ${navigationTarget!.queueCount} cars  ·  Wait: ${navigationTarget!.waitTimeMinutes.toInt()} mins',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      if (targetData != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (targetData['net_savings_php'] as num).toDouble() >= 0
                                ? const Color(0xFF10B981).withOpacity(0.2)
                                : Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (targetData['net_savings_php'] as num).toDouble() >= 0
                                  ? const Color(0xFF10B981)
                                  : Colors.redAccent,
                            ),
                          ),
                          child: Text(
                            (targetData['net_savings_php'] as num).toDouble() >= 0
                                ? '+₱${(targetData['net_savings_php'] as num).toStringAsFixed(2)}'
                                : '-₱${(targetData['net_savings_php'] as num).abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: (targetData['net_savings_php'] as num).toDouble() >= 0
                                  ? const Color(0xFF10B981)
                                  : Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _flutterTts.stop();
                        setState(() {
                          isNavigating = false;
                          navigationTarget = null;
                          _lastSpokenInstruction = '';
                        });
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: const Text('Stop Navigating', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (vehicle != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.directions_car_filled, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Profile: ${vehicle!.vehicleType}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Efficiency: ${vehicle!.fuelEfficiency.toStringAsFixed(1)} km/L  |  Idle Rate: ${vehicle!.idlingRate.toStringAsFixed(2)} L/h',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_gas_station, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('Fuel:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: fuelType,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(fontSize: 12, color: Colors.grey[900], fontWeight: FontWeight.bold),
                        items: _buildFuelDropdownItems(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => fuelType = val);
                            _fetchRoutingCalculations();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Icon(Icons.stars, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('Brand:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: preferredBrand,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(fontSize: 12, color: Colors.grey[900], fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All Brands')),
                          DropdownMenuItem(value: 'Shell', child: Text('Shell')),
                          DropdownMenuItem(value: 'Petron', child: Text('Petron')),
                          DropdownMenuItem(value: 'Phoenix', child: Text('Phoenix')),
                          DropdownMenuItem(value: 'Cleanfuel', child: Text('Cleanfuel')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => preferredBrand = val);
                            _fetchRoutingCalculations();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 10, color: Colors.black12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text('Mode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => purchaseMode = 'liters');
                      _fetchRoutingCalculations();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: purchaseMode == 'liters' ? const Color(0xFF10B981).withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: purchaseMode == 'liters' ? const Color(0xFF10B981) : Colors.black12,
                        ),
                      ),
                      child: Text(
                        'Liters',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: purchaseMode == 'liters' ? const Color(0xFF10B981) : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() => purchaseMode = 'budget');
                      _fetchRoutingCalculations();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: purchaseMode == 'budget' ? const Color(0xFF10B981).withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: purchaseMode == 'budget' ? const Color(0xFF10B981) : Colors.black12,
                        ),
                      ),
                      child: Text(
                        'Budget',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: purchaseMode == 'budget' ? const Color(0xFF10B981) : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  if (purchaseMode == 'liters') ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 26,
                          child: TextField(
                            controller: _litersController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.grey[900], fontWeight: FontWeight.bold),
                            onChanged: (val) {
                              double? parsed = double.tryParse(val);
                              if (parsed != null && parsed > 0) {
                                setState(() => liters = parsed);
                                _fetchRoutingCalculations();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('L', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 54,
                          height: 26,
                          child: TextField(
                            controller: _budgetController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              isDense: true,
                            ),
                            style: TextStyle(fontSize: 12, color: Colors.grey[900], fontWeight: FontWeight.bold),
                            onChanged: (val) {
                              double? parsed = double.tryParse(val);
                              if (parsed != null && parsed > 0) {
                                setState(() => budget = parsed);
                                _fetchRoutingCalculations();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('₱', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  ],
                ],
              ),
              const Divider(height: 10, color: Colors.black12),
              Row(
                children: [
                  const Icon(Icons.swap_calls, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('Detour Sensitivity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: priceSensitivity,
                        isExpanded: true,
                        dropdownColor: Theme.of(context).cardColor,
                        style: TextStyle(fontSize: 12, color: Colors.grey[900], fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'Medium', child: Text('Medium Detour Weight (1.0x)')),
                          DropdownMenuItem(value: 'High', child: Text('High Price / Short Detour (0.5x)')),
                          DropdownMenuItem(value: 'Low', child: Text('Low Price / Long Detour (2.0x)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => priceSensitivity = val);
                            _fetchRoutingCalculations();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Explore another location button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationExplorerScreen(
                    stations: stations,
                    vehicle: vehicle,
                    initialFuelType: fuelType,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.explore_outlined, size: 16),
            label: const Text('Explore Another Location', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 36),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: optimalStation == null
              ? const Center(child: Text('No active stations serving this fuel variant.'))
              : ListView.builder(
                  itemCount: stationsList.length,
                  itemBuilder: (context, idx) {
                    var data = stationsList[idx];
                    double netSavings = (data['net_savings_php'] as num).toDouble();
                    double detourCost = (data['travel_cost_php'] as num).toDouble();
                    double grossSavings = (data['gross_savings_php'] as num).toDouble();
                    double rawDistance = (data['raw_distance_km'] as num).toDouble();
                    int queue = data['queue_count'] ?? 0;
                    double wait = (data['wait_time_minutes'] as num).toDouble();
                    bool isOptimal = (idx == 0 && netSavings > 0);
                    bool isBaseline = data['is_baseline'] ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isOptimal 
                              ? const Color(0xFF10B981).withOpacity(0.5) 
                              : (isBaseline ? Colors.cyan.withOpacity(0.5) : Colors.grey.withOpacity(0.15)),
                          width: 1.5,
                        ),
                      ),
                      color: Theme.of(context).cardColor,
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${data['name']} – ${data['branch']}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    watchlistStationIds.contains(data['station_id']) ? Icons.favorite : Icons.favorite_border,
                                    color: watchlistStationIds.contains(data['station_id']) ? Colors.red : Colors.grey[600],
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _toggleWatchlist(data['station_id']),
                                ),
                                if (isOptimal) ...[
                                  const SizedBox(width: 6),
                                  const BadgeWidget(text: 'BEST', color: Color(0xFF10B981)),
                                ] else if (isBaseline) ...[
                                  const SizedBox(width: 6),
                                  const BadgeWidget(text: 'NEAREST', color: Colors.cyan),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () => _showSavingsBreakdownDialog(Map<String, dynamic>.from(data)),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: netSavings >= 0 ? const Color(0xFF10B981).withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: netSavings >= 0 ? const Color(0xFF10B981).withOpacity(0.2) : Colors.redAccent.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      netSavings >= 0 ? Icons.check_circle_outline : Icons.error_outline,
                                      color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                                          children: [
                                            const TextSpan(text: 'Net Detour Savings: '),
                                            TextSpan(
                                              text: netSavings >= 0 ? '+₱${netSavings.toStringAsFixed(2)}' : '-₱${netSavings.abs().toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold, 
                                                color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                                              ),
                                            ),
                                            TextSpan(
                                              text: purchaseMode == 'budget'
                                                  ? '\n(Will purchase ${data['liters_purchased']} L for ₱${budget.toStringAsFixed(0)} | Saved ₱${grossSavings.toStringAsFixed(2)} - ₱${detourCost.toStringAsFixed(2)} detour)'
                                                  : '\n(Saved ₱${grossSavings.toStringAsFixed(2)} on fuel price - ₱${detourCost.toStringAsFixed(2)} detour driving & idling)',
                                              style: TextStyle(fontSize: 10, color: Colors.grey[600], height: 1.4),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('RETAIL PRICE GRID', style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 6),
                            _buildPricesWidget(Map<String, dynamic>.from(data)),
                            const SizedBox(height: 6),
                            Text(
                              'As of: ${data['updated_at'] ?? DateTime.now().toLocal().toString().substring(0, 16)}',
                              style: TextStyle(fontSize: 10, color: Colors.grey[700], fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.directions_car, size: 12, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text('${rawDistance.toStringAsFixed(2)} km detour', style: TextStyle(fontSize: 11, color: Colors.grey[800])),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (queue > 3 ? Colors.redAccent : (queue > 0 ? Colors.amber.shade700 : const Color(0xFF10B981))).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: queue > 3 ? Colors.redAccent : (queue > 0 ? Colors.amber.shade700 : const Color(0xFF10B981)),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Queue: $queue cars · ${wait.toInt()} min wait',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: queue > 3 ? Colors.redAccent : (queue > 0 ? Colors.amber.shade900 : const Color(0xFF047857)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    final matches = stations.where((s) => s.id == data['station_id']);
                                    if (matches.isNotEmpty) {
                                      _showQueueReportDialog(matches.first);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.edit_note, size: 12, color: Color(0xFF059669)),
                                        SizedBox(width: 2),
                                        Text('Report Queue', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.black12, height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final targetStation = stations.firstWhere((s) => s.id == data['station_id']);
                                  setState(() {
                                    isNavigating = true;
                                    _autoFollowCamera = true;
                                    _navTilt = 60.0;
                                    navigationTarget = targetStation;
                                    selectedStation = targetStation;
                                    remainingDistance = AppState().getHaversineDistance(
                                      motoristLat,
                                      motoristLng,
                                      targetStation.latitude,
                                      targetStation.longitude,
                                    );
                                  });

                                  // Immediate swoop into car navigation mode
                                  _moveCamera(motoristLat, motoristLng, zoom: 18.5, bearing: currentBearing, tilt: 60.0);

                                  await _fetchRoadRoute(targetStation.latitude, targetStation.longitude);
                                  
                                  if (navigationRoutePoints.length >= 2) {
                                    currentBearing = _calculateBearing(LatLng(motoristLat, motoristLng), navigationRoutePoints[1]);
                                  }

                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _moveCamera(motoristLat, motoristLng, zoom: 18.5, bearing: currentBearing, tilt: 60.0);
                                  });

                                  if (navigationInstructions.isNotEmpty) {
                                    await _speakInstruction(navigationInstructions[0]);
                                  } else {
                                    await _speakInstruction('Starting navigation to ${targetStation.name}');
                                  }
                                },
                                icon: const Icon(Icons.navigation, size: 18),
                                label: const Text('Start Navigation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProfileView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configure Vehicle Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(r'Required to compute customized travel fuel costs ($C_{travel}$) and net detour savings.', 
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 30),

          const Text('Predefined Vehicle Catalog', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCatalogId,
            isExpanded: true,
            dropdownColor: Theme.of(context).cardColor,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[900],
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
              ),
              hintText: 'Select custom or preset template',
              hintStyle: TextStyle(color: Colors.grey[500]),
            ),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  'Custom Configuration (Manual Entry)',
                  style: TextStyle(color: Colors.grey[800], fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...catalog.map((item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${item.make} ${item.model} (${item.year}) - ${item.defaultEfficiency} km/L',
                      style: TextStyle(color: Colors.grey[900], fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
            ],
            onChanged: (val) {
              setState(() {
                _selectedCatalogId = val;
                if (val != null) {
                  final preset = catalog.firstWhere((c) => c.id == val);
                  _vehicleTypeController.text = preset.model;
                  _vehicleEfficiencyController.text = preset.defaultEfficiency.toString();
                  _vehicleIdlingRateController.text = preset.defaultIdlingRate.toString();
                }
              });
            },
          ),
          const SizedBox(height: 20),

          // Vehicle Classification Input
          TextField(
            controller: _vehicleTypeController,
            readOnly: _selectedCatalogId != null,
            style: TextStyle(
              fontSize: 14,
              color: _selectedCatalogId != null ? Colors.grey[700] : Colors.grey[900],
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'Vehicle Classification (e.g. Sedan, SUV)',
              filled: true,
              fillColor: _selectedCatalogId != null ? Colors.grey.withOpacity(0.08) : Theme.of(context).cardColor,
              suffixIcon: _selectedCatalogId != null ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) : null,
              helperText: _selectedCatalogId != null ? 'Locked to preset catalog choice' : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Fuel Efficiency Input
          TextField(
            controller: _vehicleEfficiencyController,
            readOnly: _selectedCatalogId != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 14,
              color: _selectedCatalogId != null ? Colors.grey[700] : Colors.grey[900],
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'Fuel Efficiency (km/L)',
              helperText: _selectedCatalogId != null 
                  ? 'Locked to preset catalog choice' 
                  : 'A higher value represents a more fuel-efficient vehicle.',
              filled: true,
              fillColor: _selectedCatalogId != null ? Colors.grey.withOpacity(0.08) : Theme.of(context).cardColor,
              suffixIcon: _selectedCatalogId != null ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Idling Rate Input
          TextField(
            controller: _vehicleIdlingRateController,
            readOnly: _selectedCatalogId != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 14,
              color: _selectedCatalogId != null ? Colors.grey[700] : Colors.grey[900],
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              labelText: 'Idling Rate (L/h)',
              helperText: _selectedCatalogId != null 
                  ? 'Locked to preset catalog choice' 
                  : 'Fuel burned per hour while the engine idles (e.g. 0.3 motorcycle, 1.0 sedan, 1.8 SUV/truck).',
              filled: true,
              fillColor: _selectedCatalogId != null ? Colors.grey.withOpacity(0.08) : Theme.of(context).cardColor,
              suffixIcon: _selectedCatalogId != null ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey) : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 35),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () async {
                double eff = double.tryParse(_vehicleEfficiencyController.text) ?? 12.5;
                double idlRate = double.tryParse(_vehicleIdlingRateController.text) ?? 1.20;
                await _saveVehicleProfile(_selectedCatalogId, _vehicleTypeController.text, eff, idlingRate: idlRate);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vehicle profile updated successfully!')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Save Profile Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  /// Real OCR: capture image from camera, run ML Kit text recognition,
  /// then auto-populate the price fields with detected prices.
  Future<void> _pickAndScanPhoto([ImageSource source = ImageSource.camera]) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 90,
      maxWidth: 1920,
    );
    if (picked == null) return;

    final imageFile = File(picked.path);
    setState(() {
      ocrPhotoFile = imageFile;
      ocrScanResult = null;
      _isOcrScanning = true;
    });

    try {
      final result = await OcrService().scanPriceBoard(imageFile);
      if (!mounted) return;
      setState(() {
        ocrScanResult = result;
        _isOcrScanning = false;
      });

      if (result.hasPrice) {
        // Auto-populate fields with detected prices in sorted order
        final prices = result.detectedPrices;
        if (prices.isNotEmpty) _report91Controller.text = prices[0].toStringAsFixed(2);
        if (prices.length > 1) _report95Controller.text = prices[1].toStringAsFixed(2);
        if (prices.length > 2) _reportRegDslController.text = prices[2].toStringAsFixed(2);
        if (prices.length > 3) _reportPremDslController.text = prices[3].toStringAsFixed(2);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'OCR found ${prices.length} price${prices.length > 1 ? "s" : ""}: '
                '${prices.map((p) => "₱${p.toStringAsFixed(2)}").join(", ")}',
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No prices detected in the image. Raw text: "${result.rawText.length > 80 ? result.rawText.substring(0, 80) + "..." : result.rawText}"\n'
                'Please enter prices manually.',
              ),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOcrScanning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildReportView() {
    GasStation? detectedStation;
    for (var s in stations) {
      final dist = AppState().getHaversineDistance(motoristLat, motoristLng, s.latitude, s.longitude);
      final inside = AppState().isPointInPolygon(motoristLat, motoristLng, s.geofencePolygon);
      if (inside || dist <= 0.018) {
        detectedStation = s;
        break;
      }
    }

    if (_selectedReportStationId == null && stations.isNotEmpty) {
      if (detectedStation != null) {
        _selectedReportStationId = detectedStation.id;
      } else {
        _selectedReportStationId = stations.first.id;
      }
      
      final currentStation = stations.firstWhere((s) => s.id == _selectedReportStationId);
      final p91 = currentStation.prices['regular unleaded (91)'] ?? 70.0;
      final p95 = currentStation.prices['premium unleaded(95)'] ?? 77.0;
      final pReg = currentStation.prices['regular diesel'] ?? 72.0;
      final pPrem = currentStation.prices['premium diesel'] ?? 78.0;

      _report91Controller.text = p91.toStringAsFixed(2);
      _report95Controller.text = p95.toStringAsFixed(2);
      _reportRegDslController.text = pReg.toStringAsFixed(2);
      _reportPremDslController.text = pPrem.toStringAsFixed(2);
    }

    final isNearbySelected = detectedStation != null && _selectedReportStationId == detectedStation.id;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Submit Prices (Crowdsourcing)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Select any station to report crowdsourced prices. You can report from anywhere.', 
              style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 25),

          const Text('Select Gas Station:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.withOpacity(0.15)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedReportStationId,
                isExpanded: true,
                dropdownColor: Theme.of(context).cardColor,
                style: TextStyle(fontSize: 14, color: Colors.grey[900], fontWeight: FontWeight.bold),
                items: stations.map((s) {
                  return DropdownMenuItem<String>(
                    value: s.id,
                    child: Text('${s.name} \u2013 ${s.branch}'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedReportStationId = val;
                      final currentStation = stations.firstWhere((s) => s.id == val);
                      final p91 = currentStation.prices['regular unleaded (91)'] ?? 70.0;
                      final p95 = currentStation.prices['premium unleaded(95)'] ?? 77.0;
                      final pReg = currentStation.prices['regular diesel'] ?? 72.0;
                      final pPrem = currentStation.prices['premium diesel'] ?? 78.0;

                      _report91Controller.text = p91.toStringAsFixed(2);
                      _report95Controller.text = p95.toStringAsFixed(2);
                      _reportRegDslController.text = pReg.toStringAsFixed(2);
                      _reportPremDslController.text = pPrem.toStringAsFixed(2);
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isNearbySelected ? const Color(0xFF10B981).withOpacity(0.1) : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isNearbySelected ? const Color(0xFF10B981).withOpacity(0.3) : Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  isNearbySelected ? Icons.verified : Icons.rss_feed,
                  color: isNearbySelected ? const Color(0xFF10B981) : Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNearbySelected ? 'Verified: Inside Station Lot' : 'Reporting Remotely',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isNearbySelected ? const Color(0xFF10B981) : Colors.blueAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isNearbySelected 
                          ? 'Your device GPS places you inside the geofence perimeter.'
                          : 'You are updating this station remotely from another location.',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.camera_alt, color: Theme.of(context).primaryColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Instant Report via OCR Board Photo',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            'Automatically scan prices to bypass validation checks',
                            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isOcrScanning ? null : () => _pickAndScanPhoto(ImageSource.camera),
                    icon: _isOcrScanning
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.photo_camera, size: 16),
                    label: Text(_isOcrScanning ? 'Scanning…' : 'Take Photo with Camera', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (ocrPhotoFile != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(ocrPhotoFile!, width: 54, height: 54, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  ocrScanResult?.hasPrice == true ? Icons.check_circle : Icons.warning_amber_rounded,
                                  color: ocrScanResult?.hasPrice == true ? const Color(0xFF10B981) : Colors.orange,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    ocrScanResult?.hasPrice == true
                                        ? '${ocrScanResult!.detectedPrices.length} price(s) detected'
                                        : _isOcrScanning ? 'Scanning image…' : 'No prices detected — fill manually',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: ocrScanResult?.hasPrice == true ? const Color(0xFF10B981) : Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (ocrScanResult != null && ocrScanResult!.hasPrice)
                              Text(
                                ocrScanResult!.detectedPrices.map((p) => '₱${p.toStringAsFixed(2)}').join(' · '),
                                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() { ocrPhotoFile = null; ocrScanResult = null; }),
                        child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 25),

          const Text('Enter Current Retail Prices (₱/L)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          _buildReportInputField('Unleaded 91', _report91Controller, Colors.greenAccent),
          const SizedBox(height: 12),
          _buildReportInputField('Premium Unleaded 95', _report95Controller, Colors.blueAccent),
          const SizedBox(height: 12),
          _buildReportInputField('Regular Diesel', _reportRegDslController, Colors.orangeAccent),
          const SizedBox(height: 12),
          _buildReportInputField('Premium Diesel', _reportPremDslController, Colors.purpleAccent),
          const SizedBox(height: 30),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (_selectedReportStationId == null) return;
                final targetStation = stations.firstWhere((s) => s.id == _selectedReportStationId);

                double? p91 = double.tryParse(_report91Controller.text);
                double? p95 = double.tryParse(_report95Controller.text);
                double? pReg = double.tryParse(_reportRegDslController.text);
                double? pPrem = double.tryParse(_reportPremDslController.text);

                final origP91 = targetStation.prices['regular unleaded (91)'];
                final origP95 = targetStation.prices['premium unleaded(95)'];
                final origRegDsl = targetStation.prices['regular diesel'];
                final origPremDsl = targetStation.prices['premium diesel'];

                final Map<String, double> pricesToSubmit = {};

                if (p91 != null && (origP91 == null || (p91 - origP91).abs() > 0.001)) {
                  pricesToSubmit['regular unleaded (91)'] = p91;
                }
                if (p95 != null && (origP95 == null || (p95 - origP95).abs() > 0.001)) {
                  pricesToSubmit['premium unleaded(95)'] = p95;
                }
                if (pReg != null && (origRegDsl == null || (pReg - origRegDsl).abs() > 0.001)) {
                  pricesToSubmit['regular diesel'] = pReg;
                }
                if (pPrem != null && (origPremDsl == null || (pPrem - origPremDsl).abs() > 0.001)) {
                  pricesToSubmit['premium diesel'] = pPrem;
                }

                if (pricesToSubmit.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No price modifications detected. Please edit at least one fuel price before submitting.'),
                      backgroundColor: Colors.amber,
                    ),
                  );
                  return;
                }

                try {
                  final isGeofenced = await _reportAllPrices(
                    _selectedReportStationId!,
                    pricesToSubmit,
                    photoFile: ocrPhotoFile,
                  );
                  setState(() {
                    ocrPhotoFile = null;
                    ocrScanResult = null;
                  });

                  if (!isGeofenced) {
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: Theme.of(context).cardColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: Row(
                            children: const [
                              Icon(Icons.hourglass_top_rounded, color: Colors.blueAccent, size: 26),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Recorded Successfully',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          content: const Text(
                            'Your price report has been recorded successfully. Since you are submitting away from the station geofence, the station prices will remain unchanged until 3 or more motorists submit matching prices.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                          actions: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All prices updated and reported successfully!'), backgroundColor: Colors.green),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.amber[800]),
                    );
                  }
                }
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Submit All Prices at Once', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportInputField(String label, TextEditingController controller, Color accentColor) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 14),
        prefixText: '₱ ',
        prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: accentColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.transparent,
      ),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
      ),
    );
  }
}
