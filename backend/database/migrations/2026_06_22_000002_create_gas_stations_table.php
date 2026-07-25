<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gas_stations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 255);
            $table->string('branch', 255);
            $table->decimal('latitude', 10, 8);
            $table->decimal('longitude', 11, 8);
            $table->text('geofence_polygon'); // JSON array of [lat, lng]
            $table->enum('status', ['active', 'maintenance', 'out_of_stock'])->default('active');
            $table->integer('queue_count')->default(0);
            $table->double('wait_time_minutes')->default(0.0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gas_stations');
    }
};
