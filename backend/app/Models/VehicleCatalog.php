<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class VehicleCatalog extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'vehicle_catalog';

    protected $fillable = [
        'id',
        'make',
        'model',
        'year',
        'engine_displacement',
        'fuel_type',
        'default_efficiency',
        'default_idling_rate',
    ];

    protected $casts = [
        'default_efficiency' => 'float',
        'default_idling_rate' => 'float',
    ];

    public function vehicles()
    {
        return $this->hasMany(Vehicle::class, 'catalog_id');
    }
}
