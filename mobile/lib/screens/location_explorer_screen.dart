import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gas_station.dart';
import '../models/vehicle_profile.dart';
import '../services/routing_service.dart';
import '../widgets/badge_widget.dart';

class LocationExplorerScreen extends StatefulWidget {
  final List<GasStation> stations;
  final VehicleProfile? vehicle;
  final String initialFuelType;

  const LocationExplorerScreen({
    super.key,
    required this.stations,
    required this.vehicle,
    required this.initialFuelType,
  });

  @override
  State<LocationExplorerScreen> createState() => _LocationExplorerScreenState();
}

class _LocationExplorerScreenState extends State<LocationExplorerScreen> {
  // Map & pin state
  GoogleMapController? _mapController;
  LatLng? _pinnedLocation;
  bool _mapExpanded = true;

  // Filter state
  String _fuelType = 'regular unleaded (91)';
  String _preferredBrand = 'All';
  double _liters = 10.0;
  double _budget = 500.0;
  String _purchaseMode = 'liters';
  String _priceSensitivity = 'Medium';

  // Results state
  bool _isCalculating = false;
  List<Map<String, dynamic>> _stationResults = [];
  String? _errorMessage;

  final TextEditingController _litersController = TextEditingController(text: '10.0');
  final TextEditingController _budgetController = TextEditingController(text: '500.0');

  @override
  void initState() {
    super.initState();
    // Normalize the incoming fuelType to a value that exists in our dropdown
    const validFuelTypes = [
      'regular unleaded (91)',
      'premium unleaded(95)',
      'regular diesel',
      'premium diesel',
    ];
    _fuelType = validFuelTypes.contains(widget.initialFuelType)
        ? widget.initialFuelType
        : 'regular unleaded (91)';
  }

  @override
  void dispose() {
    _litersController.dispose();
    _budgetController.dispose();
    _mapController = null;
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinnedLocation = latLng);
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 13.0),
      ));
      _computeFromPinnedLocation();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location.')),
      );
    }
  }

  Future<void> _computeFromPinnedLocation() async {
    if (_pinnedLocation == null) return;

    setState(() {
      _isCalculating = true;
      _errorMessage = null;
      _stationResults = [];
    });

    final lat = _pinnedLocation!.latitude;
    final lng = _pinnedLocation!.longitude;

    // Davao City geographical bounding box validation
    if (lat < 6.8500 || lat > 7.5500 || lng < 125.2500 || lng > 125.8500) {
      setState(() {
        _isCalculating = false;
        _errorMessage = 'Location coordinates must be within Davao City geographical boundaries.';
      });
      return;
    }

    try {
      // Always compute locally using the already-loaded stations list.
      // This is faster, works offline, and the data is already in memory.
      final result = RoutingService.computeOptimalRoutes(
        motoristLat: lat,
        motoristLng: lng,
        fuelType: _fuelType,
        purchaseMode: _purchaseMode,
        liters: _liters,
        budget: _budget,
        vehicle: widget.vehicle,
        stations: widget.stations,
        preferredBrand: _preferredBrand,
        priceSensitivity: _priceSensitivity.toLowerCase(),
      );
      if (!mounted) return;
      if (result != null && (result['stations'] as List).isNotEmpty) {
        setState(() => _stationResults = List<Map<String, dynamic>>.from(result['stations']));
      } else {
        setState(() => _errorMessage = 'No active stations found for the selected fuel type near this location.');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Calculation error: $e');
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // Pinned location
    if (_pinnedLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('pinned'),
        position: _pinnedLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: 'Exploring From Here',
          snippet: '${_pinnedLocation!.latitude.toStringAsFixed(4)}, ${_pinnedLocation!.longitude.toStringAsFixed(4)}',
        ),
      ));
    }

    // Station markers
    for (var s in widget.stations) {
      if (s.status != 'active') continue;
      // Highlight optimal station
      final isOptimal = _stationResults.isNotEmpty && _stationResults.first['station_id'] == s.id;
      markers.add(Marker(
        markerId: MarkerId('station_${s.id}'),
        position: LatLng(s.latitude, s.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          isOptimal ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueCyan,
        ),
        infoWindow: InfoWindow(
          title: '${s.name} – ${s.branch}',
          snippet: s.prices[_fuelType] != null
              ? '${_fuelType}: ₱${s.prices[_fuelType]!.toStringAsFixed(2)}'
              : 'Price unavailable',
        ),
        onTap: () {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: LatLng(s.latitude, s.longitude), zoom: 15.0),
            ),
          );
        },
      ));
    }

    return markers;
  }

  void _onMapTap(LatLng position) {
    setState(() => _pinnedLocation = position);
    _computeFromPinnedLocation();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_pin, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              'Pinned: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFF10B981) : Colors.black12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: selected ? const Color(0xFF10B981) : Colors.grey[700],
          ),
        ),
      ),
    );
  }

  void _showSavingsBreakdown(Map<String, dynamic> data) {
    final netSavings = (data['net_savings_php'] as num).toDouble();
    final grossSavings = (data['gross_savings_php'] as num).toDouble();
    final travelCost = (data['travel_cost_php'] as num).toDouble();
    final rawDist = (data['raw_distance_km'] as num).toDouble();
    final price = (data['price'] as num).toDouble();
    final litersVal = (data['liters_purchased'] as num).toDouble();
    final drivingFuel = (data['fuel_burned_driving_liters'] as num? ?? 0.0).toDouble();
    final idlingFuel = (data['fuel_burned_idling_liters'] as num? ?? 0.0).toDouble();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.calculate_outlined, size: 20),
            SizedBox(width: 8),
            Text('Savings Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _breakdownRow('Station', '${data['name']} – ${data['branch']}', isBold: true),
              _breakdownRow('Fuel Price', '₱${price.toStringAsFixed(2)}/L'),
              _breakdownRow('Liters', '${litersVal.toStringAsFixed(2)} L'),
              const Divider(height: 20),
              const Text('① Gross Fuel Savings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
              const SizedBox(height: 4),
              _breakdownRow('Formula', 'Liters × (Baseline Price − Station Price)'),
              _breakdownRow('Result', '₱${grossSavings.toStringAsFixed(2)}'),
              const Divider(height: 20),
              const Text('② Travel Detour Cost', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 4),
              _breakdownRow('Road Distance', '${(rawDist * 1.3).toStringAsFixed(2)} km (straight-line × 1.3)'),
              _breakdownRow('Fuel Driving', '${drivingFuel.toStringAsFixed(3)} L'),
              _breakdownRow('Fuel Idling', '${idlingFuel.toStringAsFixed(3)} L'),
              _breakdownRow('Travel Cost', '₱${travelCost.toStringAsFixed(2)}'),
              const Divider(height: 20),
              const Text('③ Net Detour Savings', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              _breakdownRow('Formula', 'Gross Savings − (Target Detour − Baseline Detour)'),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: netSavings >= 0
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      netSavings >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      netSavings >= 0
                          ? 'You save ₱${netSavings.toStringAsFixed(2)} by going here'
                          : 'Going here costs ₱${netSavings.abs().toStringAsFixed(2)} more',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.explore_outlined, size: 20),
            SizedBox(width: 8),
            Text('Location Explorer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (_pinnedLocation != null)
            TextButton.icon(
              onPressed: _computeFromPinnedLocation,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          if (_pinnedLocation == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, size: 16, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap anywhere on the map to explore gas stations from that location.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // Map section
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _mapExpanded ? 260 : 120,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(7.1907, 125.4553), // Davao City center
                    zoom: 12.0,
                  ),
                  onMapCreated: (c) => _mapController = c,
                  markers: _buildMarkers(),
                  onTap: _onMapTap,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),

                // Collapse / expand toggle
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _mapExpanded = !_mapExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _mapExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _mapExpanded ? 'Collapse Map' : 'Expand Map',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Pinned coords overlay
                if (_pinnedLocation != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_pin, size: 12, color: Colors.lightBlueAccent),
                          const SizedBox(width: 4),
                          Text(
                            '${_pinnedLocation!.latitude.toStringAsFixed(4)}, ${_pinnedLocation!.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                // My Location button
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'explorer_my_location',
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    onPressed: _goToMyLocation,
                    tooltip: 'Use My Location',
                    child: const Icon(Icons.my_location, size: 18),
                  ),
                ),
              ],
            ),
          ),

          // Filters panel
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            color: theme.cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Fuel + Brand
                Row(
                  children: [
                    const Icon(Icons.local_gas_station, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Fuel:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(width: 6),
                     Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _fuelType,
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.grey[900], fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'regular unleaded (91)', child: Text('Regular Unleaded (91)')),
                            DropdownMenuItem(value: 'premium unleaded(95)', child: Text('Premium Unleaded (95)')),
                            DropdownMenuItem(value: 'regular diesel', child: Text('Regular Diesel')),
                            DropdownMenuItem(value: 'premium diesel', child: Text('Premium Diesel')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _fuelType = val);
                              _computeFromPinnedLocation();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.stars, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Brand:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _preferredBrand,
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.grey[900], fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'All', child: Text('All')),
                            DropdownMenuItem(value: 'Shell', child: Text('Shell')),
                            DropdownMenuItem(value: 'Petron', child: Text('Petron')),
                            DropdownMenuItem(value: 'Phoenix', child: Text('Phoenix')),
                            DropdownMenuItem(value: 'Cleanfuel', child: Text('Cleanfuel')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _preferredBrand = val);
                              _computeFromPinnedLocation();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 10, color: Colors.black12),
                // Row 2: Mode + Amount
                Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text('Mode:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const SizedBox(width: 6),
                    _buildFilterChip('Liters', _purchaseMode == 'liters', () {
                      setState(() => _purchaseMode = 'liters');
                      _computeFromPinnedLocation();
                    }),
                    const SizedBox(width: 4),
                    _buildFilterChip('Budget', _purchaseMode == 'budget', () {
                      setState(() => _purchaseMode = 'budget');
                      _computeFromPinnedLocation();
                    }),
                    const SizedBox(width: 8),
                    if (_purchaseMode == 'liters') ...[
                      SizedBox(
                        width: 40,
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
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.grey[900], fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            final p = double.tryParse(val);
                            if (p != null && p > 0) {
                              setState(() => _liters = p);
                              _computeFromPinnedLocation();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text('L', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    ] else ...[
                      SizedBox(
                        width: 50,
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
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.grey[900], fontWeight: FontWeight.bold),
                          onChanged: (val) {
                            final p = double.tryParse(val);
                            if (p != null && p > 0) {
                              setState(() => _budget = p);
                              _computeFromPinnedLocation();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text('₱', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    ],
                    const Spacer(),
                    const Icon(Icons.swap_calls, size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _priceSensitivity,
                          isExpanded: true,
                          dropdownColor: theme.cardColor,
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white : Colors.grey[900], fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'High', child: Text('Short Detour')),
                            DropdownMenuItem(value: 'Medium', child: Text('Balanced')),
                            DropdownMenuItem(value: 'Low', child: Text('Long Detour OK')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _priceSensitivity = val);
                              _computeFromPinnedLocation();
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

          const Divider(height: 1, color: Colors.black12),

          // Results list
          Expanded(
            child: _buildResultsArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_pinnedLocation == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_searching, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No location pinned yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[500]),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap on the map above to pick a spot,\nor use the GPS button to use your current location.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    if (_isCalculating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Calculating best stations…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      itemCount: _stationResults.length,
      itemBuilder: (context, idx) {
        final data = _stationResults[idx];
        final netSavings = (data['net_savings_php'] as num).toDouble();
        final rawDistance = (data['raw_distance_km'] as num).toDouble();
        final int queue = data['queue_count'] ?? 0;
        final double wait = (data['wait_time_minutes'] as num).toDouble();
        final bool isOptimal = (idx == 0 && netSavings > 0);
        final bool isBaseline = data['is_baseline'] ?? false;
        final double price = (data['price'] as num).toDouble();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isOptimal
                  ? const Color(0xFF10B981).withValues(alpha: 0.5)
                  : (isBaseline ? Colors.cyan.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.15)),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Station name + badges + savings
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['name']} – ${data['branch']}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                const SizedBox(height: 8),

                // Price + savings row
                Row(
                  children: [
                    // Fuel price
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '₱${price.toStringAsFixed(2)}/L',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Clickable net savings
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showSavingsBreakdown(data),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: netSavings >= 0
                                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                                : Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: netSavings >= 0
                                  ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                  : Colors.redAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                netSavings >= 0 ? Icons.savings_outlined : Icons.money_off_outlined,
                                size: 13,
                                color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  netSavings >= 0
                                      ? '+₱${netSavings.toStringAsFixed(2)} net savings'
                                      : '-₱${netSavings.abs().toStringAsFixed(2)} extra cost',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: netSavings >= 0 ? const Color(0xFF10B981) : Colors.redAccent,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.info_outline, size: 12, color: Colors.grey[400]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Distance + queue
                Row(
                  children: [
                    const Icon(Icons.directions_car, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${rawDistance.toStringAsFixed(2)} km away',
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                          const SizedBox(width: 4),
                          Text(
                            'Queue: $queue cars · ${wait.toInt()}m wait',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: queue > 3 ? Colors.redAccent : (queue > 0 ? Colors.amber.shade900 : const Color(0xFF047857)),
                            ),
                          ),
                        ],
                      ),
                    ),

                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
