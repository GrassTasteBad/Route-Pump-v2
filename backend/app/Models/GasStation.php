<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class GasStation extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'gas_stations';

    protected $fillable = [
        'id',
        'name',
        'branch',
        'latitude',
        'longitude',
        'geofence_polygon',
        'status',
        'fuel_availability',
        'queue_count',
        'wait_time_minutes',
    ];

    protected $casts = [
        'geofence_polygon'   => 'array',
        'fuel_availability'  => 'array',
        'latitude'           => 'float',
        'longitude'          => 'float',
    ];

    public function prices()
    {
        return $this->hasMany(FuelPrice::class, 'station_id');
    }

    public function anomalyLogs()
    {
        return $this->hasMany(AnomalyLog::class, 'station_id');
    }

    public function telemetryLogs()
    {
        return $this->hasMany(TelemetryLog::class, 'station_id');
    }

    public function employees()
    {
        return $this->hasMany(User::class, 'station_id');
    }
}
