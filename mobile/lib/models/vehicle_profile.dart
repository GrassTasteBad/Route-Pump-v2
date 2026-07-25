class VehicleProfile {
  final String id;
  final String? catalogId;
  final String vehicleType;
  final double fuelEfficiency;
  final double idlingRate;

  VehicleProfile({
    required this.id,
    this.catalogId,
    required this.vehicleType,
    required this.fuelEfficiency,
    this.idlingRate = 1.20,
  });

  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    return VehicleProfile(
      id: json['id'],
      catalogId: json['catalog_id'],
      vehicleType: json['vehicle_type'] ?? 'Sedan',
      fuelEfficiency: (json['fuel_efficiency'] as num).toDouble(),
      idlingRate: (json['idling_rate'] as num?)?.toDouble() ?? 1.20,
    );
  }
}
