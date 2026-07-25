<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TelemetryLog extends Model
{
    use HasFactory;

    protected $table = 'telemetry_logs';

    public $timestamps = false; // We use a custom 'timestamp' column in migration

    protected $fillable = [
        'user_id',
        'station_id',
        'velocity',
        'is_inside_fence',
        'timestamp',
    ];

    protected $casts = [
        'is_inside_fence' => 'boolean',
        'timestamp' => 'datetime',
        'velocity' => 'float',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function station()
    {
        return $this->belongsTo(GasStation::class, 'station_id');
    }
}
