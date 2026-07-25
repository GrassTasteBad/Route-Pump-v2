<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\GasStation;
use App\Models\FuelPrice;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MCDMRoutingTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private GasStation $stationShell;
    private GasStation $stationPetron;

    protected function setUp(): void
    {
        parent::setUp();

        $this->user = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Test Motorist',
            'email' => 'motorist@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
        ]);

        // Create a Shell station (closer but slightly more expensive)
        $this->stationShell = GasStation::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Shell Lanang',
            'branch' => 'Lanang',
            'address' => 'Lanang Davao City',
            'latitude' => 7.090, // Baseline: on route
            'longitude' => 125.630,
            'status' => 'active',
            'geofence_polygon' => [[0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0]],
        ]);

        // Create a Petron station (farther detour, but cheaper)
        $this->stationPetron = GasStation::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Petron Lanang',
            'branch' => 'Lanang Detour',
            'address' => 'Lanang Davao City',
            'latitude' => 7.120, // Detour: 5km away
            'longitude' => 125.630,
            'status' => 'active',
            'geofence_polygon' => [[0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0]],
        ]);

        // Add prices for both
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->stationShell->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 75.00, // baseline price
            'status' => 'merchant_verified',
            'reported_by' => $this->user->id,
            'created_at' => now(),
        ]);

        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->stationPetron->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 71.00, // target price (cheaper)
            'status' => 'merchant_verified',
            'reported_by' => $this->user->id,
            'created_at' => now(),
        ]);
    }

    /**
     * Test preferred brand filtering strictly restricts results to Petron.
     */
    public function test_preferred_brand_filters_stations_strictly(): void
    {
        Sanctum::actingAs($this->user);

        // Request routing with preferred brand "Petron"
        $response = $this->getJson('/api/gas-stations/routing?' . http_build_query([
            'latitude' => 7.090,
            'longitude' => 125.630,
            'fuel_type' => 'regular unleaded (91)',
            'liters' => 30,
            'preferred_brand' => 'Petron',
        ]));

        $response->assertStatus(200);
        $data = $response->json();

        // Should ONLY contain Petron Lanang
        $this->assertCount(1, $data['stations']);
        $this->assertEquals('Petron Lanang', $data['stations'][0]['name']);
    }

    /**
     * Test price sensitivity weights travel detour costs.
     */
    public function test_price_sensitivity_weights_detour_overhead(): void
    {
        Sanctum::actingAs($this->user);

        // Case 1: High price sensitivity (sensFactor = 0.5, detour is cheaper net-cost)
        $responseHigh = $this->getJson('/api/gas-stations/routing?' . http_build_query([
            'latitude' => 7.090,
            'longitude' => 125.630,
            'fuel_type' => 'regular unleaded (91)',
            'liters' => 30,
            'price_sensitivity' => 'high',
        ]));
        $responseHigh->assertStatus(200);
        $dataHigh = $responseHigh->json();

        // Case 2: Low price sensitivity (sensFactor = 2.0, detour travel cost is doubled, so baseline is better)
        $responseLow = $this->getJson('/api/gas-stations/routing?' . http_build_query([
            'latitude' => 7.090,
            'longitude' => 125.630,
            'fuel_type' => 'regular unleaded (91)',
            'liters' => 30,
            'price_sensitivity' => 'low',
        ]));
        $responseLow->assertStatus(200);
        $dataLow = $responseLow->json();

        // Verify that the Petron station has higher net savings under High price sensitivity
        // than under Low price sensitivity.
        $petronHigh = collect($dataHigh['stations'])->firstWhere('name', 'Petron Lanang');
        $petronLow = collect($dataLow['stations'])->firstWhere('name', 'Petron Lanang');

        $this->assertNotNull($petronHigh);
        $this->assertNotNull($petronLow);

        $this->assertGreaterThan(
            $petronLow['net_savings_php'],
            $petronHigh['net_savings_php'],
            "High price sensitivity should result in higher net savings for cheaper detours than Low price sensitivity."
        );
    }
}
