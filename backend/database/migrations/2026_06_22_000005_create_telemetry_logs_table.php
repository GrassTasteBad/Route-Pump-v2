<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('telemetry_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUuid('station_id')->nullable()->constrained('gas_stations')->nullOnDelete();
            $table->decimal('velocity', 5, 2); // km/h
            $table->boolean('is_inside_fence')->default(false);
            $table->timestamp('timestamp');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('telemetry_logs');
    }
};
