<?php

namespace App\Http\Controllers;

use App\Models\Vehicle;
use App\Models\VehicleCatalog;
use App\Services\FuelEconomyClient;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class VehicleController extends Controller
{
    private FuelEconomyClient $fuelEconomyClient;

    public function __construct(FuelEconomyClient $fuelEconomyClient)
    {
        $this->fuelEconomyClient = $fuelEconomyClient;
    }
    public function getCatalog()
    {
        return response(VehicleCatalog::all(), 200);
    }

    public function createCatalog(Request $request)
    {
        $request->validate([
            'make' => 'required|string',
            'model' => 'required|string',
            'year' => 'required|integer',
            'engine_displacement' => 'nullable|string',
            'fuel_type' => 'required|string|in:unleaded,diesel',
            'default_efficiency' => 'required|numeric',
            'default_idling_rate' => 'nullable|numeric|min:0.1|max:10',
        ]);

        $catalog = VehicleCatalog::create(array_merge($request->all(), [
            'id' => (string) Str::uuid()
        ]));

        return response($catalog, 201);
    }

    public function getProfile(Request $request)
    {
        $vehicle = $request->user()->vehicle;
        if (!$vehicle) {
            return response(['message' => 'No vehicle profile configured'], 404);
        }
        return response($vehicle->load('catalog'), 200);
    }

    public function updateProfile(Request $request)
    {
        $fields = $request->validate([
            'catalog_id' => 'nullable|string|exists:vehicle_catalog,id',
            'vehicle_type' => 'required|string',
            'fuel_efficiency' => 'required|numeric',
            'idling_rate' => 'nullable|numeric|min:0.1|max:10',
        ]);

        $user = $request->user();
        
        $vehicle = Vehicle::updateOrCreate(
            ['user_id' => $user->id],
            [
                'id' => $user->vehicle?->id ?? (string) Str::uuid(),
                'catalog_id' => $fields['catalog_id'] ?? null,
                'vehicle_type' => $fields['vehicle_type'],
                'fuel_efficiency' => $fields['fuel_efficiency'],
                'idling_rate' => $fields['idling_rate'] ?? 1.20,
            ]
        );

        return response($vehicle->load('catalog'), 200);
    }

    public function getFeYears()
    {
        return response($this->fuelEconomyClient->getYears(), 200);
    }

    public function getFeMakes(Request $request)
    {
        $request->validate(['year' => 'required|string']);
        return response($this->fuelEconomyClient->getMakes($request->year), 200);
    }

    public function getFeModels(Request $request)
    {
        $request->validate([
            'year' => 'required|string',
            'make' => 'required|string',
        ]);
        return response($this->fuelEconomyClient->getModels($request->year, $request->make), 200);
    }

    public function getFeOptions(Request $request)
    {
        $request->validate([
            'year' => 'required|string',
            'make' => 'required|string',
            'model' => 'required|string',
        ]);
        return response($this->fuelEconomyClient->getOptions($request->year, $request->make, $request->model), 200);
    }

    public function getFeVehicle($id)
    {
        $details = $this->fuelEconomyClient->getVehicleDetails($id);
        if (!$details) {
            return response(['message' => 'Vehicle details not found on fueleconomy.gov'], 404);
        }
        return response($details, 200);
    }

    public function syncCatalog(Request $request)
    {
        $popularMakes = ['Toyota', 'Honda', 'Ford', 'Chevrolet', 'Nissan', 'Hyundai', 'Kia', 'Subaru', 'Mazda', 'Mitsubishi'];
        $year = '2023';

        // Round 1: Fetch models for popular makes concurrently
        $modelResponses = \Illuminate\Support\Facades\Http::pool(function (\Illuminate\Http\Client\Pool $pool) use ($popularMakes, $year) {
            foreach ($popularMakes as $make) {
                $pool->as($make)->accept('application/json')
                    ->get("https://www.fueleconomy.gov/ws/rest/vehicle/menu/model?year={$year}&make=" . urlencode($make));
            }
        });

        $modelsToSync = [];
        foreach ($popularMakes as $make) {
            $res = $modelResponses[$make];
            if (!$res->successful()) {
                continue;
            }
            $json = $res->json() ?? [];
            $menuItems = $this->normalizeMenu($json);
            if (empty($menuItems)) {
                continue;
            }
            // Take first 5 models for this make to expand the database catalog
            $sliced = array_slice($menuItems, 0, 5);
            foreach ($sliced as $item) {
                $modelsToSync[] = [
                    'make' => $make,
                    'model' => $item['value']
                ];
            }
        }

        if (empty($modelsToSync)) {
            return response(['message' => 'Failed to fetch models from FuelEconomy.gov'], 502);
        }

        // Round 2: Fetch options for these models concurrently
        $optionResponses = \Illuminate\Support\Facades\Http::pool(function (\Illuminate\Http\Client\Pool $pool) use ($modelsToSync, $year) {
            foreach ($modelsToSync as $index => $item) {
                $pool->as($index)->accept('application/json')
                    ->get("https://www.fueleconomy.gov/ws/rest/vehicle/menu/options?year={$year}&make=" . urlencode($item['make']) . "&model=" . urlencode($item['model']));
            }
        });

        $vehiclesToSync = [];
        foreach ($modelsToSync as $index => $item) {
            $res = $optionResponses[$index];
            if (!$res->successful()) {
                continue;
            }
            $json = $res->json() ?? [];
            $options = $this->normalizeMenu($json);
            if (empty($options)) {
                continue;
            }
            // Take the first option's vehicle ID
            $vehiclesToSync[$index] = $options[0]['value'];
        }

        if (empty($vehiclesToSync)) {
            return response(['message' => 'Failed to fetch model options from FuelEconomy.gov'], 502);
        }

        // Round 3: Fetch vehicle details concurrently
        $detailResponses = \Illuminate\Support\Facades\Http::pool(function (\Illuminate\Http\Client\Pool $pool) use ($vehiclesToSync) {
            foreach ($vehiclesToSync as $index => $vehicleId) {
                $pool->as($index)->accept('application/json')
                    ->get("https://www.fueleconomy.gov/ws/rest/vehicle/{$vehicleId}");
            }
        });

        $createdCount = 0;
        $syncedCount = 0;

        foreach ($vehiclesToSync as $index => $vehicleId) {
            $res = $detailResponses[$index];
            if (!$res->successful()) {
                continue;
            }
            $data = $res->json();
            if (empty($data)) {
                continue;
            }

            $mpg = (double) ($data['comb08'] ?? 20.0);
            $efficiencyKml = round($mpg * 0.425143707, 2);
            $rawFuelType = strtolower($data['fuelType'] ?? '');
            $fuelType = str_contains($rawFuelType, 'diesel') ? 'diesel' : 'unleaded';
            $make = $data['make'] ?? 'Unknown';
            $model = $data['model'] ?? 'Unknown';
            $vehicleYear = (int) ($data['year'] ?? 0);
            $engineDisplacement = isset($data['displ']) ? $data['displ'] . 'L' : null;

            // Check if already exists locally
            $exists = VehicleCatalog::where('make', $make)
                ->where('model', $model)
                ->where('year', $vehicleYear)
                ->where('engine_displacement', $engineDisplacement)
                ->exists();

            if (!$exists) {
                VehicleCatalog::create([
                    'id' => (string) Str::uuid(),
                    'make' => $make,
                    'model' => $model,
                    'year' => $vehicleYear,
                    'engine_displacement' => $engineDisplacement,
                    'fuel_type' => $fuelType,
                    'default_efficiency' => $efficiencyKml,
                    'default_idling_rate' => $fuelType === 'diesel' ? 1.80 : 1.20,
                ]);
                $createdCount++;
            }
            $syncedCount++;
        }

        return response([
            'message' => "Successfully synced {$syncedCount} vehicles from FuelEconomy.gov. Added {$createdCount} new types to database.",
            'catalog' => VehicleCatalog::all()
        ], 200);
    }

    private function normalizeMenu(array $response): array
    {
        if (empty($response) || !isset($response['menuItem'])) {
            return [];
        }
        $items = $response['menuItem'];
        if (isset($items['text']) && isset($items['value'])) {
            return [$items];
        }
        return (array) $items;
    }
}
