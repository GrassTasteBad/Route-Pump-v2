<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

class FuelEconomyClient
{
    private const BASE_URL = 'https://www.fueleconomy.gov/ws/rest';

    /**
     * Normalize FuelEconomy.gov's menuItem list, which can be an array, a single object, or null.
     */
    private function normalizeMenu(array $response): array
    {
        if (empty($response) || !isset($response['menuItem'])) {
            return [];
        }

        $items = $response['menuItem'];

        // If it's a single object (associative array with 'text' key), wrap it in a list
        if (isset($items['text']) && isset($items['value'])) {
            return [$items];
        }

        return (array) $items;
    }

    public function getYears(): array
    {
        $response = Http::withHeaders(['Accept' => 'application/json'])
            ->get(self::BASE_URL . '/vehicle/menu/year');

        if (!$response->successful()) {
            return [];
        }

        return $this->normalizeMenu($response->json() ?? []);
    }

    public function getMakes(string $year): array
    {
        $response = Http::withHeaders(['Accept' => 'application/json'])
            ->get(self::BASE_URL . '/vehicle/menu/make', [
                'year' => $year
            ]);

        if (!$response->successful()) {
            return [];
        }

        return $this->normalizeMenu($response->json() ?? []);
    }

    public function getModels(string $year, string $make): array
    {
        $response = Http::withHeaders(['Accept' => 'application/json'])
            ->get(self::BASE_URL . '/vehicle/menu/model', [
                'year' => $year,
                'make' => $make
            ]);

        if (!$response->successful()) {
            return [];
        }

        return $this->normalizeMenu($response->json() ?? []);
    }

    public function getOptions(string $year, string $make, string $model): array
    {
        $response = Http::withHeaders(['Accept' => 'application/json'])
            ->get(self::BASE_URL . '/vehicle/menu/options', [
                'year' => $year,
                'make' => $make,
                'model' => $model
            ]);

        if (!$response->successful()) {
            return [];
        }

        return $this->normalizeMenu($response->json() ?? []);
    }

    public function getVehicleDetails(string $id): ?array
    {
        $response = Http::withHeaders(['Accept' => 'application/json'])
            ->get(self::BASE_URL . "/vehicle/{$id}");

        if (!$response->successful()) {
            return null;
        }

        $data = $response->json();
        if (empty($data)) {
            return null;
        }

        // Convert MPG to km/L
        $mpg = (double) ($data['comb08'] ?? 20.0);
        $efficiencyKml = round($mpg * 0.425143707, 2);

        // Map fuel type: regular/premium gasoline -> unleaded, diesel -> diesel
        $rawFuelType = strtolower($data['fuelType'] ?? '');
        $fuelType = str_contains($rawFuelType, 'diesel') ? 'diesel' : 'unleaded';

        return [
            'fueleconomy_id' => $id,
            'make' => $data['make'] ?? 'Unknown',
            'model' => $data['model'] ?? 'Unknown',
            'year' => (int) ($data['year'] ?? 0),
            'engine_displacement' => isset($data['displ']) ? $data['displ'] . 'L' : null,
            'fuel_type' => $fuelType,
            'default_efficiency' => $efficiencyKml,
            'default_idling_rate' => $fuelType === 'diesel' ? 1.80 : 1.20,
        ];
    }
}
