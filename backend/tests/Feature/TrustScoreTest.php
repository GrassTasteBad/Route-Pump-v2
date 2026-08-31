<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\GasStation;
use App\Models\FuelPrice;
use App\Models\AnomalyLog;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TrustScoreTest extends TestCase
{
    use RefreshDatabase;

    private User $motorist;
    private GasStation $station;

    protected function setUp(): void
    {
        parent::setUp();

        // Create standard motorist
        $this->motorist = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'John Doe',
            'email' => 'john@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 50,
        ]);

        // Create gas station
        $this->station = GasStation::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Phoenix Davao',
            'branch' => 'Lanang',
            'address' => 'Lanang Davao City',
            'latitude' => 7.098,
            'longitude' => 125.632,
            'status' => 'active',
            'geofence_polygon' => [[0.0, 0.0], [0.0, 10.0], [10.0, 10.0], [10.0, 0.0]],
        ]);
    }

    /**
     * Test normal price report increments trust score by 2.
     */
    public function test_normal_price_report_increments_trust_score(): void
    {
        Sanctum::actingAs($this->motorist);

        // Pre-create a historical price to avoid standard deviation anomaly flag
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 75.00,
            'status' => 'merchant_verified',
            'reported_by' => $this->motorist->id,
            'created_at' => now()->subDays(1),
        ]);

        $response = $this->postJson("/api/gas-stations/{$this->station->id}/prices", [
            'fuel_type' => 'regular unleaded (91)',
            'price' => 75.00,
            'latitude' => 7.098,
            'longitude' => 125.632,
        ]);

        $response->assertStatus(201);
        $this->motorist->refresh();
        $this->assertEquals(52, $this->motorist->trust_score);
    }

    /**
     * Test low trust score auto-flags anomaly.
     */
    public function test_low_trust_score_auto_flags_anomaly(): void
    {
        $this->motorist->trust_score = 25;
        $this->motorist->save();

        Sanctum::actingAs($this->motorist);

        $response = $this->postJson("/api/gas-stations/{$this->station->id}/prices", [
            'fuel_type' => 'regular unleaded (91)',
            'price' => 75.00,
            'latitude' => 7.098,
            'longitude' => 125.632,
        ]);

        $response->assertStatus(202); // 202 accepted (flagged)
        $this->assertDatabaseHas('anomaly_logs', [
            'station_id' => $this->station->id,
            'status' => 'pending',
        ]);
    }

    /**
     * Test high trust score or OCR verified bypasses support confirm checks.
     */
    public function test_ocr_or_high_trust_bypasses_confirmations(): void
    {
        // 1. Case: Standard user with 50 trust (needs confirmation)
        Sanctum::actingAs($this->motorist);
        
        $priceId = (string) \Illuminate\Support\Str::uuid();
        FuelPrice::create([
            'id' => $priceId,
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 60.00,
            'reported_by' => $this->motorist->id,
            'status' => 'crowdsourced',
            'is_inside_geofence' => false,
            'created_at' => now(),
        ]);

        // Fetch valid prices: should return null because no confirmation exists
        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'regular diesel');
        $this->assertNull($latest);

        // 2. Case: High trust user (trust >= 80)
        $highTrustUser = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'High Trust Motorist',
            'email' => 'hightrust@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 85,
        ]);

        $priceId2 = (string) \Illuminate\Support\Str::uuid();
        FuelPrice::create([
            'id' => $priceId2,
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 62.00,
            'reported_by' => $highTrustUser->id,
            'status' => 'crowdsourced',
            'created_at' => now(),
        ]);

        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'regular diesel');
        $this->assertNotNull($latest);
        $this->assertEquals(62.00, (double)$latest->price);

        // 3. Case: OCR Verified Price (bypasses check even for normal motorist)
        $priceId3 = (string) \Illuminate\Support\Str::uuid();
        FuelPrice::create([
            'id' => $priceId3,
            'station_id' => $this->station->id,
            'fuel_type' => 'premium unleaded(95)',
            'price' => 80.00,
            'reported_by' => $this->motorist->id,
            'status' => 'crowdsourced',
            'ocr_verified' => true,
            'created_at' => now(),
        ]);

        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'premium unleaded(95)');
        $this->assertNotNull($latest);
        $this->assertEquals(80.00, (double)$latest->price);
    }

    /**
     * Test anomaly resolution and dismissal trust score adjustments.
     */
    public function test_anomaly_action_adjusts_trust_score(): void
    {
        $admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Admin User',
            'email' => 'admin@example.com',
            'password' => bcrypt('password'),
            'role' => 'admin',
        ]);

        $price = FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 120.00, // Outlier
            'reported_by' => $this->motorist->id,
            'status' => 'crowdsourced',
            'created_at' => now(),
        ]);

        $anomaly = AnomalyLog::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'price_id' => $price->id,
            'description' => 'Outlier detected',
            'status' => 'pending',
        ]);

        Sanctum::actingAs($admin);

        // 1. Resolve increases trust by 10
        $this->postJson("/api/anomalies/{$anomaly->id}/resolve")->assertStatus(200);
        $this->motorist->refresh();
        $this->assertEquals(60, $this->motorist->trust_score);

        // Reset anomaly and test dismissal
        $anomaly->status = 'pending';
        $anomaly->save();

        // 2. Dismiss decreases trust by 15
        $this->postJson("/api/anomalies/{$anomaly->id}/dismiss")->assertStatus(200);
        $this->motorist->refresh();
        $this->assertEquals(45, $this->motorist->trust_score);
    }

    /**
     * Test admin can deactivate user and deactivated user cannot login.
     */
    public function test_admin_can_deactivate_user_and_login_is_blocked(): void
    {
        $admin = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Admin User',
            'email' => 'admin_test@example.com',
            'password' => bcrypt('password'),
            'role' => 'admin',
        ]);

        Sanctum::actingAs($admin);

        // 1. Deactivate motorist
        $response = $this->deleteJson("/api/users/{$this->motorist->id}");
        $response->assertStatus(200);
        $response->assertJsonFragment(['message' => 'User account deactivated successfully.']);

        $this->motorist->refresh();
        $this->assertEquals('deactivated', $this->motorist->status);

        // 2. Try logging in as deactivated user
        $loginResponse = $this->postJson('/api/login', [
            'email' => $this->motorist->email,
            'password' => 'password',
        ]);
        $loginResponse->assertStatus(403);
        $loginResponse->assertJsonFragment(['message' => 'Your account has been deactivated.']);

        // 3. Reactivate motorist
        $activateResponse = $this->postJson("/api/users/{$this->motorist->id}/activate");
        $activateResponse->assertStatus(200);
        $activateResponse->assertJsonFragment(['message' => 'User account activated successfully.']);

        $this->motorist->refresh();
        $this->assertEquals('active', $this->motorist->status);

        // 4. Try logging in again after activation
        $reLoginResponse = $this->postJson('/api/login', [
            'email' => $this->motorist->email,
            'password' => 'password',
        ]);
        $reLoginResponse->assertStatus(200);
        $reLoginResponse->assertJsonStructure(['token', 'user']);
    }

    /**
     * Test price report succeeds from remote coordinates (no geofence restriction).
     */
    public function test_remote_price_report_without_geofence_restriction(): void
    {
        Sanctum::actingAs($this->motorist);

        // Pre-create historical price
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular unleaded (91)',
            'price' => 75.00,
            'status' => 'merchant_verified',
            'reported_by' => $this->motorist->id,
            'created_at' => now()->subDays(1),
        ]);

        // Submit from coordinates far away (outside ~100m geofence)
        $response = $this->postJson("/api/gas-stations/{$this->station->id}/prices", [
            'fuel_type' => 'regular unleaded (91)',
            'price' => 79.00,
            'latitude' => 7.5000,
            'longitude' => 125.5000,
        ]);

        $response->assertStatus(201);
        $response->assertJsonFragment(['is_inside_geofence' => false]);

        // Station active price must STAY 75.00 (unchanged) on backend & admin side!
        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'regular unleaded (91)');
        $this->assertEquals(75.00, (double)$latest->price);
    }

    /**
     * Test price report submitted within geofence range updates station price immediately.
     */
    public function test_geofenced_price_report_updates_immediately(): void
    {
        Sanctum::actingAs($this->motorist);

        // Submit price with coordinates matching station position (inside geofence)
        $response = $this->postJson("/api/gas-stations/{$this->station->id}/prices", [
            'fuel_type' => 'regular unleaded (91)',
            'price' => 68.50,
            'latitude' => (float)$this->station->latitude,
            'longitude' => (float)$this->station->longitude,
        ]);

        $response->assertStatus(201);

        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'regular unleaded (91)');
        $this->assertNotNull($latest);
        $this->assertEquals(68.50, (double)$latest->price);
    }

    /**
     * Test three or more distinct motorists must submit exact same price remotely to change station price.
     */
    public function test_three_motorists_consensus_required_to_change_price(): void
    {
        $m1 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Motorist 1',
            'email' => 'm1@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 50,
        ]);
        $m2 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Motorist 2',
            'email' => 'm2@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 50,
        ]);
        $m3 = User::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'name' => 'Motorist 3',
            'email' => 'm3@example.com',
            'password' => bcrypt('password'),
            'role' => 'motorist',
            'trust_score' => 50,
        ]);

        // Fuel type: regular diesel (remote submissions with is_inside_geofence = false)
        // 1st motorist submits 64.00 remotely
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 64.00,
            'reported_by' => $m1->id,
            'status' => 'crowdsourced',
            'is_inside_geofence' => false,
            'created_at' => now(),
        ]);
        // 1 motorist remotely: price should NOT be active yet (leaves price as is)
        $this->assertNull(FuelPrice::getLatestValidPrice($this->station->id, 'regular diesel'));

        // 2nd motorist submits exact same 64.00 remotely
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 64.00,
            'reported_by' => $m2->id,
            'status' => 'crowdsourced',
            'is_inside_geofence' => false,
            'created_at' => now(),
        ]);
        // 2 motorists remotely: price should STILL NOT be active
        $this->assertNull(FuelPrice::getLatestValidPrice($this->station->id, 'regular diesel'));

        // 3rd motorist submits exact same 64.00 remotely
        FuelPrice::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'station_id' => $this->station->id,
            'fuel_type' => 'regular diesel',
            'price' => 64.00,
            'reported_by' => $m3->id,
            'status' => 'crowdsourced',
            'is_inside_geofence' => false,
            'created_at' => now(),
        ]);
        // 3 motorists remotely: price IS active and changes the gas station price!
        $latest = FuelPrice::getLatestValidPrice($this->station->id, 'regular diesel');
        $this->assertNotNull($latest);
        $this->assertEquals(64.00, (double)$latest->price);
    }
}
