<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('fuel_prices', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('station_id')->constrained('gas_stations')->cascadeOnDelete();
            $table->enum('fuel_type', ['regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel']);
            $table->decimal('price', 5, 2);
            $table->foreignUuid('reported_by')->constrained('users')->cascadeOnDelete();
            $table->enum('status', ['crowdsourced', 'merchant_verified'])->default('crowdsourced');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('fuel_prices');
    }
};
