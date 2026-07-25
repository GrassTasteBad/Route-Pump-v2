<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vehicles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('user_id')->constrained('users')->cascadeOnDelete();
            $table->foreignUuid('catalog_id')->nullable()->constrained('vehicle_catalog')->nullOnDelete();
            $table->string('vehicle_type', 100);
            $table->decimal('fuel_efficiency', 5, 2); // km/L
            $table->decimal('idling_rate', 4, 2)->default(1.20); // Liters per hour while idling
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vehicles');
    }
};
