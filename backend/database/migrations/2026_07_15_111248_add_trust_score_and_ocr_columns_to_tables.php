<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->integer('trust_score')->default(50);
        });

        Schema::table('fuel_prices', function (Blueprint $table) {
            $table->string('image_path')->nullable();
            $table->boolean('ocr_verified')->default(false);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('trust_score');
        });

        Schema::table('fuel_prices', function (Blueprint $table) {
            $table->dropColumn(['image_path', 'ocr_verified']);
        });
    }
};
