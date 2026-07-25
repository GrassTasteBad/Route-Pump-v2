<?php

namespace Database\Seeders;

use App\Models\User;
use App\Models\VehicleCatalog;
use App\Models\GasStation;
use App\Models\FuelPrice;
use Illuminate\Database\Seeder;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // 1. Seed Vehicle Catalog
        $catalogItems = [
            [
                'id' => (string) Str::uuid(),
                'make' => 'Toyota',
                'model' => 'Vios',
                'year' => 2022,
                'engine_displacement' => '1.3L',
                'fuel_type' => 'unleaded',
                'default_efficiency' => 14.50,
                'default_idling_rate' => 1.00, // 1.3L engine, A/C on
            ],
            [
                'id' => (string) Str::uuid(),
                'make' => 'Mitsubishi',
                'model' => 'Mirage',
                'year' => 2021,
                'engine_displacement' => '1.2L',
                'fuel_type' => 'unleaded',
                'default_efficiency' => 16.20,
                'default_idling_rate' => 0.80, // Small 1.2L engine
            ],
            [
                'id' => (string) Str::uuid(),
                'make' => 'Honda',
                'model' => 'Civic',
                'year' => 2023,
                'engine_displacement' => '1.5T',
                'fuel_type' => 'unleaded',
                'default_efficiency' => 12.80,
                'default_idling_rate' => 1.20, // 1.5L turbo
            ],
            [
                'id' => (string) Str::uuid(),
                'make' => 'Isuzu',
                'model' => 'D-Max',
                'year' => 2020,
                'engine_displacement' => '3.0L',
                'fuel_type' => 'diesel',
                'default_efficiency' => 11.20,
                'default_idling_rate' => 1.80, // Large 3.0L diesel
            ],
            [
                'id' => (string) Str::uuid(),
                'make' => 'Suzuki',
                'model' => 'Raider R150',
                'year' => 2022,
                'engine_displacement' => '150cc',
                'fuel_type' => 'unleaded',
                'default_efficiency' => 38.00,
                'default_idling_rate' => 0.30, // Motorcycle, minimal idle consumption
            ],
            [
                'id' => (string) Str::uuid(),
                'make' => 'Toyota',
                'model' => 'Fortuner',
                'year' => 2022,
                'engine_displacement' => '2.8L',
                'fuel_type' => 'diesel',
                'default_efficiency' => 10.50,
                'default_idling_rate' => 1.80, // Large 2.8L diesel SUV
            ],
        ];

        foreach ($catalogItems as $item) {
            VehicleCatalog::create($item);
        }

        // 2. Seed Gas Stations in Davao City with coordinates and custom geofence polygons
        $petronUuid = (string) Str::uuid();
        $shellUuid = (string) Str::uuid();
        $caltexUuid = (string) Str::uuid();
        $phoenixUuid = (string) Str::uuid();

        $stations = [
            [
                'id' => $petronUuid,
                'name' => 'Petron',
                'branch' => 'Roxas Avenue',
                'latitude' => 7.07060000,
                'longitude' => 125.61520000,
                'status' => 'active',
            ],
            [
                'id' => $shellUuid,
                'name' => 'Shell',
                'branch' => 'JP Laurel Ave',
                'latitude' => 7.08740000,
                'longitude' => 125.61670000,
                'status' => 'active',
            ],
            [
                'id' => $caltexUuid,
                'name' => 'Caltex',
                'branch' => 'Quirino Ave',
                'latitude' => 7.06550000,
                'longitude' => 125.60800000,
                'status' => 'active',
            ],
            [
                'id' => $phoenixUuid,
                'name' => 'Phoenix',
                'branch' => 'Ecoland',
                'latitude' => 7.05120000,
                'longitude' => 125.59450000,
                'status' => 'active',
            ]
        ];

        foreach ($stations as $station) {
            $geofencePolygon = $this->generateFixedGeofence((double)$station['latitude'], (double)$station['longitude']);
            GasStation::create(array_merge($station, [
                'geofence_polygon' => $geofencePolygon
            ]));
        }

        // 3. Seed Users
        $admin = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'System Admin',
            'email' => 'admin@routepump.com',
            'password' => bcrypt('password'),
            'role' => 'admin',
        ]);

        $motorist = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'John Motorist',
            'email' => 'motorist@routepump.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
        ]);

        // Link partner user to Petron Roxas Ave
        $partner = User::create([
            'id' => (string) Str::uuid(),
            'name' => 'Petron Employee',
            'email' => 'partner@routepump.com',
            'password' => bcrypt('password'),
            'role' => 'partner',
            'station_id' => $petronUuid,
        ]);

        // Create standard motorists vehicle profile
        $motorist->vehicle()->create([
            'id' => (string) Str::uuid(),
            'catalog_id' => VehicleCatalog::where('model', 'Vios')->first()->id,
            'vehicle_type' => 'Sedan',
            'fuel_efficiency' => 14.50,
        ]);

        // 4. Seed Initial Fuel Prices
        $fuelPrices = [
            // Petron (Baseline Station)
            ['station_id' => $petronUuid, 'fuel_type' => 'regular diesel', 'price' => 75.00, 'reported_by' => $partner->id, 'status' => 'merchant_verified'],
            ['station_id' => $petronUuid, 'fuel_type' => 'premium diesel', 'price' => 81.00, 'reported_by' => $partner->id, 'status' => 'merchant_verified'],
            ['station_id' => $petronUuid, 'fuel_type' => 'regular unleaded (91)', 'price' => 71.00, 'reported_by' => $partner->id, 'status' => 'merchant_verified'],
            ['station_id' => $petronUuid, 'fuel_type' => 'premium unleaded(95)', 'price' => 78.00, 'reported_by' => $partner->id, 'status' => 'merchant_verified'],

            // Shell (Cheaper Unleaded, premium)
            ['station_id' => $shellUuid, 'fuel_type' => 'regular diesel', 'price' => 74.50, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $shellUuid, 'fuel_type' => 'premium diesel', 'price' => 80.50, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $shellUuid, 'fuel_type' => 'regular unleaded (91)', 'price' => 68.50, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $shellUuid, 'fuel_type' => 'premium unleaded(95)', 'price' => 75.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],

            // Caltex (Slightly cheaper diesel)
            ['station_id' => $caltexUuid, 'fuel_type' => 'regular diesel', 'price' => 72.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $caltexUuid, 'fuel_type' => 'premium diesel', 'price' => 78.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $caltexUuid, 'fuel_type' => 'regular unleaded (91)', 'price' => 70.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $caltexUuid, 'fuel_type' => 'premium unleaded(95)', 'price' => 77.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],

            // Phoenix (Ecoland)
            ['station_id' => $phoenixUuid, 'fuel_type' => 'regular diesel', 'price' => 74.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $phoenixUuid, 'fuel_type' => 'premium diesel', 'price' => 79.50, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $phoenixUuid, 'fuel_type' => 'regular unleaded (91)', 'price' => 69.00, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
            ['station_id' => $phoenixUuid, 'fuel_type' => 'premium unleaded(95)', 'price' => 76.50, 'reported_by' => $admin->id, 'status' => 'crowdsourced'],
        ];

        foreach ($fuelPrices as $price) {
            FuelPrice::create(array_merge($price, [
                'id' => (string) Str::uuid(),
                'created_at' => now(),
            ]));
        }
    }

    private function generateFixedGeofence($lat, $lng, $radiusMeters = 15)
    {
        $earthRadius = 6371000; // meters
        $points = [];
        $numPoints = 16;
        for ($i = 0; $i < $numPoints; $i++) {
            $angle = deg2rad(($i * 360) / $numPoints);
            $dLat = ($radiusMeters / $earthRadius) * cos($angle);
            $dLng = ($radiusMeters / ($earthRadius * cos(deg2rad($lat)))) * sin($angle);
            $points[] = [
                round($lat + rad2deg($dLat), 8),
                round($lng + rad2deg($dLng), 8),
            ];
        }
        return $points;
    }
}
