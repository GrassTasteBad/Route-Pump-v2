<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations to add indexes for database optimization and efficient querying.
     */
    public function up(): void
    {
        Schema::table('fuel_prices', function (Blueprint $table) {
            $table->index(['station_id', 'fuel_type', 'created_at'], 'idx_fp_station_type_created');
            $table->index(['reported_by', 'created_at'], 'idx_fp_reporter_created');
        });

        Schema::table('gas_stations', function (Blueprint $table) {
            $table->index(['latitude', 'longitude'], 'idx_gs_coordinates');
            $table->index('status', 'idx_gs_status');
        });

        Schema::table('telemetry_logs', function (Blueprint $table) {
            $table->index(['user_id', 'timestamp'], 'idx_tl_user_timestamp');
            $table->index(['station_id', 'timestamp'], 'idx_tl_station_timestamp');
        });

        Schema::table('anomaly_logs', function (Blueprint $table) {
            $table->index(['station_id', 'status'], 'idx_al_station_status');
            $table->index('price_id', 'idx_al_price');
        });

        Schema::table('watchlists', function (Blueprint $table) {
            $table->unique(['user_id', 'station_id'], 'unique_user_station_watchlist');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('fuel_prices', function (Blueprint $table) {
            $table->dropIndex('idx_fp_station_type_created');
            $table->dropIndex('idx_fp_reporter_created');
        });

        Schema::table('gas_stations', function (Blueprint $table) {
            $table->dropIndex('idx_gs_coordinates');
            $table->dropIndex('idx_gs_status');
        });

        Schema::table('telemetry_logs', function (Blueprint $table) {
            $table->dropIndex('idx_tl_user_timestamp');
            $table->dropIndex('idx_tl_station_timestamp');
        });

        Schema::table('anomaly_logs', function (Blueprint $table) {
            $table->dropIndex('idx_al_station_status');
            $table->dropIndex('idx_al_price');
        });

        Schema::table('watchlists', function (Blueprint $table) {
            $table->dropUnique('unique_user_station_watchlist');
        });
    }
};
