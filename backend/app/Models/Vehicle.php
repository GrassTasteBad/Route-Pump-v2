<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Vehicle extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'vehicles';

    protected $fillable = [
        'id',
        'user_id',
        'catalog_id',
        'vehicle_type',
        'fuel_efficiency',
        'idling_rate',
    ];

    protected $casts = [
        'fuel_efficiency' => 'float',
        'idling_rate' => 'float',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function catalog()
    {
        return $this->belongsTo(VehicleCatalog::class, 'catalog_id');
    }
}
