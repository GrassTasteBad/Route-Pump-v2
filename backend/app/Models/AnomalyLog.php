<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AnomalyLog extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'anomaly_logs';

    protected $fillable = [
        'id',
        'station_id',
        'price_id',
        'description',
        'status',
    ];

    public function station()
    {
        return $this->belongsTo(GasStation::class, 'station_id');
    }

    public function price()
    {
        return $this->belongsTo(FuelPrice::class, 'price_id');
    }
}
