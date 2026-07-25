<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\GasStation;
use App\Models\FuelPrice;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AnalyticsTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();

        $this->admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Admin User',
            'email' => 'admin@example.com',
            'password' => bcrypt('password'),
            'role' => 'admin',
        ]);

        $station = GasStation::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Test Station',
            'branch' => 'Main',
            'address' => 'Davao City',
            'latitude' => 7.00,
            'longitude' => 125.00,
            'status' => 'active',
            'geofence_polygon' => [[0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0]],
        ]);

        // Insert prices
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $station->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 70.00,
            'status' => 'merchant_verified',
            'reported_by' => $this->admin->id,
            'created_at' => now(),
        ]);

        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $station->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 72.00,
            'status' => 'merchant_verified',
            'reported_by' => $this->admin->id,
            'created_at' => now(),
        ]);

        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $station->id,
            'fuel_type' => 'premium unleaded(95)',
            'price' => 80.00,
            'status' => 'merchant_verified',
            'reported_by' => $this->admin->id,
            'created_at' => now(),
        ]);

        // Insert vehicles with specific efficiency values
        Vehicle::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => $this->admin->id,
            'make' => 'Toyota',
            'model' => 'Vios',
            'year' => 2020,
            'vehicle_type' => 'sedan',
            'fuel_efficiency' => 12.00,
            'idling_rate' => 1.0,
        ]);

        $user2 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'User Two',
            'email' => 'user2@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
        ]);

        Vehicle::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => $user2->id,
            'make' => 'Honda',
            'model' => 'Civic',
            'year' => 2021,
            'vehicle_type' => 'sedan',
            'fuel_efficiency' => 14.00,
            'idling_rate' => 1.2,
        ]);
    }

    /**
     * Test analytics dashboard returns correct data matching the database records.
     */
    public function test_dashboard_analytics_data_integrity(): void
    {
        Sanctum::actingAs($this->admin);

        $response = $this->getJson('/api/analytics/dashboard');

        $response->assertStatus(200);
        $data = $response->json();

        // 1. Verify Fuel Type distribution count
        $this->assertEquals(2, $data['fuel_type_distribution']['regular unleaded (91)']);
        $this->assertEquals(1, $data['fuel_type_distribution']['premium unleaded(95)']);
        $this->assertEquals(0, $data['fuel_type_distribution']['regular diesel']);

        // 2. Verify Average Vehicle Efficiency = (12 + 14) / 2 = 13.0
        $this->assertEquals(13.0, $data['vehicle_stats']['average_efficiency']);
        $this->assertEquals(2, $data['vehicle_stats']['total_vehicles']);

        // 3. Verify total user count = admin + user2 = 2
        $this->assertEquals(2, $data['user_stats']['total_users']);
    }
}
