<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vehicle_catalog', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('make', 100);
            $table->string('model', 100);
            $table->integer('year');
            $table->string('engine_displacement', 50)->nullable();
            $table->enum('fuel_type', ['unleaded', 'diesel']);
            $table->decimal('default_efficiency', 5, 2); // km/L
            $table->decimal('default_idling_rate', 4, 2)->default(1.20); // Liters per hour while idling
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vehicle_catalog');
    }
};
