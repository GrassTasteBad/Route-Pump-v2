<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('gas_stations', function (Blueprint $table) {
            // JSON column storing availability per fuel type, e.g.:
            // {"regular unleaded (91)": true, "premium unleaded(95)": false, ...}
            $table->json('fuel_availability')->nullable()->after('status');
        });
    }

    public function down(): void
    {
        Schema::table('gas_stations', function (Blueprint $table) {
            $table->dropColumn('fuel_availability');
        });
    }
};
