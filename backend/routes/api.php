<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\VehicleController;
use App\Http\Controllers\GasStationController;
use App\Http\Controllers\TelemetryController;
use App\Http\Controllers\AnomalyController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\WatchlistController;
use App\Http\Controllers\AnalyticsController;
use Illuminate\Support\Facades\Route;

// Public Authentication Routes
Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login'])->name('login');

// Protected API Routes
Route::middleware('auth:sanctum')->group(function () {
    // Current User Profile
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);

    // Vehicle Catalog & Profiler
    Route::get('/vehicle-catalog', [VehicleController::class, 'getCatalog']);
    Route::post('/vehicle-catalog', [VehicleController::class, 'createCatalog']);
    Route::post('/vehicle-catalog/sync', [VehicleController::class, 'syncCatalog']);
    Route::get('/vehicle', [VehicleController::class, 'getProfile']);
    Route::post('/vehicle', [VehicleController::class, 'updateProfile']);

    // FuelEconomy.gov API proxies
    Route::get('/fueleconomy/years', [VehicleController::class, 'getFeYears']);
    Route::get('/fueleconomy/makes', [VehicleController::class, 'getFeMakes']);
    Route::get('/fueleconomy/models', [VehicleController::class, 'getFeModels']);
    Route::get('/fueleconomy/options', [VehicleController::class, 'getFeOptions']);
    Route::get('/fueleconomy/vehicle/{id}', [VehicleController::class, 'getFeVehicle']);

    // Gas Station APIs
    Route::get('/gas-stations', [GasStationController::class, 'index']);
    Route::get('/gas-stations/live', [GasStationController::class, 'liveUpdates']);
    Route::post('/gas-stations', [GasStationController::class, 'store']);
    Route::delete('/gas-stations/{id}', [GasStationController::class, 'destroy']);
    Route::post('/gas-stations/{id}/status', [GasStationController::class, 'updateStatus']);
    Route::post('/gas-stations/{id}/fuel-availability', [GasStationController::class, 'updateFuelAvailability']);
    Route::post('/gas-stations/{id}/prices', [GasStationController::class, 'reportPrice']);
    Route::post('/gas-stations/{id}/queue', [GasStationController::class, 'updateQueue']);
    
    // Net-Cost Routing & Estimation API
    Route::get('/gas-stations/routing', [GasStationController::class, 'routing']);

    // Participatory Telemetry Logger API
    Route::post('/telemetry', [TelemetryController::class, 'log']);
    Route::post('/telemetry/flush', [TelemetryController::class, 'flush']);

    // Leaderboards & Trust Score API
    Route::get('/leaderboard', [UserController::class, 'leaderboard']);

    // Price Anomaly Auditing & Moderation APIs
    Route::get('/anomalies', [AnomalyController::class, 'index']);
    Route::post('/anomalies/{id}/resolve', [AnomalyController::class, 'resolve']);
    Route::post('/anomalies/{id}/dismiss', [AnomalyController::class, 'dismiss']);

    // User Management APIs (Admin)
    Route::get('/users', [UserController::class, 'index']);
    Route::post('/users', [UserController::class, 'store']);
    Route::delete('/users/{id}', [UserController::class, 'destroy']);

    // Watchlist Favorites APIs
    Route::get('/watchlist', [WatchlistController::class, 'index']);
    Route::post('/watchlist', [WatchlistController::class, 'store']);
    Route::delete('/watchlist/{id}', [WatchlistController::class, 'destroy']);

    // Analytics Dashboard APIs
    Route::get('/analytics/dashboard', [AnalyticsController::class, 'dashboard']);
});
