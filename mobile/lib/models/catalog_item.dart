class CatalogItem {
  final String id;
  final String make;
  final String model;
  final int year;
  final String? displacement;
  final String fuelType;
  final double defaultEfficiency;
  final double defaultIdlingRate;

  CatalogItem({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    this.displacement,
    required this.fuelType,
    required this.defaultEfficiency,
    this.defaultIdlingRate = 1.20,
  });

  factory CatalogItem.fromJson(Map<String, dynamic> json) {
    return CatalogItem(
      id: json['id'],
      make: json['make'],
      model: json['model'],
      year: json['year'],
      displacement: json['engine_displacement'],
      fuelType: json['fuel_type'],
      defaultEfficiency: (json['default_efficiency'] as num).toDouble(),
      defaultIdlingRate: (json['default_idling_rate'] as num?)?.toDouble() ?? 1.20,
    );
  }
}
