<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class FuelPrice extends Model
{
    use HasFactory, HasUuids;

    protected $table = 'fuel_prices';

    protected $fillable = [
        'id',
        'station_id',
        'fuel_type',
        'price',
        'reported_by',
        'status',
        'created_at',
        'image_path',
        'ocr_verified',
    ];

    public $timestamps = false; // we use custom created_at/timestamps if we want, or default database timestamp. But we have created_at and let's set updated_at as well or let Laravel handle it.
    
    protected $casts = [
        'price' => 'float',
    ];
    
    // Let's configure custom timestamps or let Laravel use its defaults. The migration has $table->timestamps(). So we should keep default timestamps or manage them.
    // Wait, the migration has $table->timestamps(). So let's enable Laravel timestamps.
    public $timestampsEnabled = true;

    public function station()
    {
        return $this->belongsTo(GasStation::class, 'station_id');
    }

    public function reporter()
    {
        return $this->belongsTo(User::class, 'reported_by');
    }

    public function anomalyLogs()
    {
        return $this->hasMany(AnomalyLog::class, 'price_id');
    }

    /**
     * Get the latest valid price for a specific station and fuel type.
     */
    public static function getLatestValidPrice(string $stationId, string $fuelType): ?FuelPrice
    {
        return self::where('station_id', $stationId)
            ->where('fuel_type', $fuelType)
            ->orderBy('created_at', 'desc')
            ->whereNotExists(function ($query) {
                $query->selectRaw(1)
                    ->from('anomaly_logs')
                    ->whereColumn('anomaly_logs.price_id', 'fuel_prices.id')
                    ->whereIn('anomaly_logs.status', ['pending', 'dismissed']);
            })
            ->with('reporter')
            ->get()
            ->first(function ($priceRecord) {
                if ($priceRecord->status === 'merchant_verified') {
                    return true;
                }
                if ($priceRecord->reporter && $priceRecord->reporter->role === 'admin') {
                    return true;
                }
                if ($priceRecord->ocr_verified) {
                    return true;
                }
                if ($priceRecord->reporter && $priceRecord->reporter->trust_score >= 80) {
                    return true;
                }
                
                // Crowdsourced: check for at least 1 supporting submission from another user within 3 days
                $supportingCount = self::where('station_id', $priceRecord->station_id)
                    ->where('fuel_type', $priceRecord->fuel_type)
                    ->where('price', $priceRecord->price)
                    ->where('id', '!=', $priceRecord->id)
                    ->where('reported_by', '!=', $priceRecord->reported_by)
                    ->where('status', 'crowdsourced')
                    ->whereBetween('created_at', [
                        \Carbon\Carbon::parse($priceRecord->created_at)->subDays(3),
                        \Carbon\Carbon::parse($priceRecord->created_at)->addDays(3)
                    ])
                    ->distinct('reported_by')
                    ->count('reported_by');
                    
                return $supportingCount >= 1;
            });
    }
}

