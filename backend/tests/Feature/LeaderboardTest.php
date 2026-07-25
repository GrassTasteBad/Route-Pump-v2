<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\GasStation;
use App\Models\FuelPrice;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class LeaderboardTest extends TestCase
{
    use RefreshDatabase;

    public function test_leaderboard_endpoint_returns_ranked_motorists()
    {
        $motorist1 = User::create([
            'name' => 'Alice Motorist',
            'email' => 'alice@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 95,
        ]);

        $motorist2 = User::create([
            'name' => 'Bob Motorist',
            'email' => 'bob@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 75,
        ]);

        $response = $this->actingAs($motorist1, 'sanctum')
            ->getJson('/api/leaderboard');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'my_stats' => ['rank', 'name', 'trust_score', 'tier'],
                'leaderboard' => [
                    '*' => ['rank', 'name', 'trust_score', 'tier']
                ]
            ]);

        $this->assertEquals(1, $response->json('my_stats.rank'));
        $this->assertEquals('Platinum Reporter', $response->json('my_stats.tier'));
    }

    public function test_manual_queue_reporting_updates_station_and_trust_score()
    {
        $station = GasStation::create([
            'name' => 'Shell',
            'branch' => 'Test Branch',
            'latitude' => 7.0700,
            'longitude' => 125.6100,
            'geofence_polygon' => [[7.0700, 125.6100]],
            'status' => 'active',
            'queue_count' => 0,
            'wait_time_minutes' => 0,
        ]);

        $motorist = User::create([
            'name' => 'Charlie Motorist',
            'email' => 'charlie@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 60,
        ]);

        $response = $this->actingAs($motorist, 'sanctum')
            ->postJson("/api/gas-stations/{$station->id}/queue", [
                'queue_count' => 5,
                'latitude' => 7.0700,
                'longitude' => 125.6100,
            ]);

        $response->assertStatus(200)
            ->assertJson([
                'queue_count' => 5,
                'wait_time_minutes' => 15.0,
            ]);

        $this->assertEquals(61, $motorist->fresh()->trust_score);
    }

    public function test_davao_city_bounding_box_validation_rejects_out_of_bounds_telemetry()
    {
        $motorist = User::create([
            'name' => 'Out of Bounds User',
            'email' => 'out@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
        ]);

        // Manila coordinates (outside Davao City)
        $response = $this->actingAs($motorist, 'sanctum')
            ->postJson('/api/telemetry', [
                'latitude' => 14.5995,
                'longitude' => 120.9842,
                'velocity' => 30.0,
            ]);

        $response->assertStatus(422)
            ->assertJson([
                'message' => 'Telemetry coordinates must be within Davao City geographical boundaries.'
            ]);
    }
}
