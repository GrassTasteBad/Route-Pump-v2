import 'package:flutter/material.dart';
import '../models/catalog_item.dart';
import '../models/vehicle_profile.dart';

class VehicleProfileScreen extends StatefulWidget {
  final List<CatalogItem> catalog;
  final VehicleProfile? currentProfile;
  final Future<void> Function(String? catalogId, String type, double efficiency, double idlingRate) onSave;

  const VehicleProfileScreen({
    super.key,
    required this.catalog,
    required this.currentProfile,
    required this.onSave,
  });

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  String? _selectedCatalogId;
  late TextEditingController _vehicleTypeController;
  late TextEditingController _vehicleEfficiencyController;
  late TextEditingController _vehicleIdlingRateController;

  @override
  void initState() {
    super.initState();
    _selectedCatalogId = widget.currentProfile?.catalogId;
    _vehicleTypeController = TextEditingController(text: widget.currentProfile?.vehicleType ?? '');
    _vehicleEfficiencyController = TextEditingController(
      text: widget.currentProfile != null ? widget.currentProfile!.fuelEfficiency.toString() : '',
    );
    _vehicleIdlingRateController = TextEditingController(
      text: widget.currentProfile != null ? widget.currentProfile!.idlingRate.toString() : '1.20',
    );
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _vehicleEfficiencyController.dispose();
    _vehicleIdlingRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Configure Vehicle Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(r'Required to compute customized travel fuel costs ($C_{travel}$) and net detour savings.', 
              style: TextStyle(color: Colors.grey[700], fontSize: 14)),
          const SizedBox(height: 30),

          // Predefined Vehicle Catalog
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
              ...widget.catalog.map((item) => DropdownMenuItem(
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
                  final preset = widget.catalog.firstWhere((c) => c.id == val);
                  _vehicleTypeController.text = preset.model;
                  _vehicleEfficiencyController.text = preset.defaultEfficiency.toString();
                  _vehicleIdlingRateController.text = preset.defaultIdlingRate.toString();
                }
              });
            },
          ),
          const SizedBox(height: 20),

          // Custom Input Type
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

          // Custom Efficiency Input
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
                await widget.onSave(_selectedCatalogId, _vehicleTypeController.text, eff, idlRate);
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
}
