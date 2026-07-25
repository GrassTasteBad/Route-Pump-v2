import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../models/gas_station.dart';
import '../widgets/badge_widget.dart';
import 'auth_gate.dart';

class PartnerDashboard extends StatefulWidget {
  const PartnerDashboard({super.key});

  @override
  State<PartnerDashboard> createState() => _PartnerDashboardState();
}

class _PartnerDashboardState extends State<PartnerDashboard> {
  bool _isLoading = false;
  GasStation? branchInfo;

  final _regUnleaded91Controller  = TextEditingController();
  final _premUnleaded95Controller = TextEditingController();
  final _regDieselController      = TextEditingController();
  final _premDieselController     = TextEditingController();
  String activeStatus = 'active';

  // Per-fuel availability (local mirror of branchInfo.fuelAvailability)
  Map<String, bool> _fuelAvailability = {
    for (final t in kFuelTypes) t: true,
  };

  static const _fuelLabels = {
    'regular unleaded (91)': 'Regular Unleaded 91',
    'premium unleaded(95)':  'Premium Unleaded 95',
    'regular diesel':        'Regular Diesel',
    'premium diesel':        'Premium Diesel',
  };

  static const _fuelColors = {
    'regular unleaded (91)': Colors.green,
    'premium unleaded(95)':  Colors.blue,
    'regular diesel':        Colors.orange,
    'premium diesel':        Colors.purple,
  };

  @override
  void initState() {
    super.initState();
    _fetchBranchInfo();
  }

  Future<void> _fetchBranchInfo() async {
    setState(() { _isLoading = true; });
    final partnerStationId = AppState().currentUser?['station_id'];
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/gas-stations'), headers: AppState().getHeaders());
      if (res.statusCode == 200) {
        final List parsed = jsonDecode(res.body);
        final stationsList = parsed.map((x) => GasStation.fromJson(x)).toList();
        setState(() {
          branchInfo = stationsList.firstWhere((s) => s.id == partnerStationId);
          _regUnleaded91Controller.text  = branchInfo?.prices['regular unleaded (91)']?.toString() ?? '';
          _premUnleaded95Controller.text = branchInfo?.prices['premium unleaded(95)']?.toString() ?? '';
          _regDieselController.text      = branchInfo?.prices['regular diesel']?.toString() ?? '';
          _premDieselController.text     = branchInfo?.prices['premium diesel']?.toString() ?? '';
          activeStatus       = branchInfo?.status ?? 'active';
          _fuelAvailability  = Map<String, bool>.from(branchInfo?.fuelAvailability ?? {
            for (final t in kFuelTypes) t: true,
          });
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load branch info. Check server connection.'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _updatePrices() async {
    if (branchInfo == null) return;
    setState(() => _isLoading = true);
    try {
      final priceUpdates = <Future<void>>[];
      final p91     = double.tryParse(_regUnleaded91Controller.text) ?? 0.0;
      final p95     = double.tryParse(_premUnleaded95Controller.text) ?? 0.0;
      final pReg    = double.tryParse(_regDieselController.text) ?? 0.0;
      final pPrem   = double.tryParse(_premDieselController.text) ?? 0.0;
      if (p91   > 0) priceUpdates.add(_sendPriceUpdate('regular unleaded (91)', p91));
      if (p95   > 0) priceUpdates.add(_sendPriceUpdate('premium unleaded(95)',  p95));
      if (pReg  > 0) priceUpdates.add(_sendPriceUpdate('regular diesel',        pReg));
      if (pPrem > 0) priceUpdates.add(_sendPriceUpdate('premium diesel',        pPrem));
      if (priceUpdates.isNotEmpty) await Future.wait(priceUpdates);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prices updated (Merchant Verified).'), backgroundColor: Colors.green));
      _fetchBranchInfo();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPriceUpdate(String type, double price) async {
    if (price <= 0) return;
    if (AppState().isSandboxMode) {
      setState(() { branchInfo!.prices[type] = price; });
      return;
    }
    await http.post(
      Uri.parse('$apiBaseUrl/gas-stations/${branchInfo!.id}/prices'),
      headers: AppState().getHeaders(),
      body: jsonEncode({'fuel_type': type, 'price': price}),
    );
  }

  Future<void> _updateStatus(String status) async {
    if (branchInfo == null) return;
    if (AppState().isSandboxMode) {
      setState(() { branchInfo!.status = status; activeStatus = status; });
      return;
    }
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/gas-stations/${branchInfo!.id}/status'),
        headers: AppState().getHeaders(),
        body: jsonEncode({'status': status}),
      );
      if (res.statusCode == 200) {
        setState(() => activeStatus = status);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Station status updated.'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('Status update error $e');
    }
  }

  Future<void> _toggleFuelAvailability(String fuelType, bool available) async {
    // Optimistic local update
    setState(() => _fuelAvailability[fuelType] = available);

    if (AppState().isSandboxMode) {
      branchInfo?.fuelAvailability[fuelType] = available;
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/gas-stations/${branchInfo!.id}/fuel-availability'),
        headers: AppState().getHeaders(),
        body: jsonEncode({'fuel_type': fuelType, 'available': available}),
      );
      if (res.statusCode != 200) {
        // Revert on failure
        setState(() => _fuelAvailability[fuelType] = !available);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update fuel availability.'), backgroundColor: Colors.redAccent));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(available
                ? '${_fuelLabels[fuelType]} marked as Available ✓'
                : '${_fuelLabels[fuelType]} marked as Unavailable'),
            backgroundColor: available ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (e) {
      setState(() => _fuelAvailability[fuelType] = !available);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBranchInfo,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () {
              AppState().token = '';
              AppState().currentUser = null;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthGate()));
            },
          ),
        ],
      ),
      body: _isLoading || branchInfo == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Branch title card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(branchInfo!.name,
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            ),
                            const BadgeWidget(text: 'MERCHANT AUTH', color: Colors.green),
                          ],
                        ),
                        Text('${branchInfo!.branch} Branch', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Active Queue Wait: ', style: TextStyle(fontSize: 13)),
                            Text(
                              '${branchInfo!.queueCount} vehicles (${branchInfo!.waitTimeMinutes.toInt()} mins)',
                              style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Station Status Override ──────────────────────────────
                  const Text('Station Status Override', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildStatusBtn('active',       'Active',       Colors.green),
                      const SizedBox(width: 10),
                      _buildStatusBtn('maintenance',  'Maintenance',  Colors.amber),
                      const SizedBox(width: 10),
                      _buildStatusBtn('out_of_stock', 'Out of Fuel',  Colors.redAccent),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // ── Fuel Type Availability ───────────────────────────────
                  const Text('Fuel Type Availability', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    'Toggle which fuel types are currently in stock at your station.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: kFuelTypes.asMap().entries.map((entry) {
                        final idx      = entry.key;
                        final fuelType = entry.value;
                        final label    = _fuelLabels[fuelType]!;
                        final color    = _fuelColors[fuelType]!;
                        final isAvail  = _fuelAvailability[fuelType] ?? true;
                        final isLast   = idx == kFuelTypes.length - 1;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10, height: 10,
                                    decoration: BoxDecoration(
                                      color: isAvail ? color : Colors.grey[400],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                              color: isAvail ? null : Colors.grey,
                                            )),
                                        Text(
                                          isAvail ? 'In stock — visible to motorists' : 'Marked unavailable — hidden from routing',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isAvail ? Colors.green[700] : Colors.orange[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: isAvail,
                                    activeColor: color,
                                    onChanged: (val) => _toggleFuelAvailability(fuelType, val),
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast) Divider(height: 1, indent: 38, endIndent: 16, color: Colors.grey.withOpacity(0.2)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Manage Prices ────────────────────────────────────────
                  const Text('Manage Station Fuel Prices (PHP/Liter)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  _buildPriceField('Regular Unleaded (91)',  _regUnleaded91Controller,  Colors.green),
                  const SizedBox(height: 15),
                  _buildPriceField('Premium Unleaded (95)', _premUnleaded95Controller,  Colors.blue),
                  const SizedBox(height: 15),
                  _buildPriceField('Regular Diesel',        _regDieselController,       Colors.orange),
                  const SizedBox(height: 15),
                  _buildPriceField('Premium Diesel',        _premDieselController,      Colors.purple),
                  const SizedBox(height: 30),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _updatePrices,
                      icon: const Icon(Icons.publish),
                      label: const Text('Publish Official Prices', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildPriceField(String label, TextEditingController controller, Color accentColor) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: '$label Price',
        labelStyle: TextStyle(color: accentColor, fontWeight: FontWeight.w600),
        prefixText: '₱ ',
        prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: accentColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 2),
        ),
      ),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
      ),
    );
  }

  Widget _buildStatusBtn(String status, String label, Color color) {
    final bool isSelected = activeStatus == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateStatus(status),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Theme.of(context).cardColor,
            border: Border.all(color: isSelected ? color : Colors.grey.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? color : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
