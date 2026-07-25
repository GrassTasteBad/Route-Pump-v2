<?php

namespace App\Models;

use Laravel\Sanctum\HasApiTokens;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable, HasUuids;

    protected $fillable = [
        'id',
        'name',
        'email',
        'password',
        'role',
        'station_id',
        'trust_score',
        'status',
    ];

    protected $hidden = [
        'password',
        'remember_token',
    ];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function vehicle()
    {
        return $this->hasOne(Vehicle::class);
    }

    public function reportedPrices()
    {
        return $this->hasMany(FuelPrice::class, 'reported_by');
    }

    public function telemetryLogs()
    {
        return $this->hasMany(TelemetryLog::class);
    }

    public function station()
    {
        return $this->belongsTo(GasStation::class, 'station_id');
    }

    public function watchlists()
    {
        return $this->hasMany(Watchlist::class);
    }
}
