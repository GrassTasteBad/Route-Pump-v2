<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Add 'pending_photo_review' to the fuel_prices status column.
     * SQLite does not support ALTER COLUMN, so we update the CHECK constraint
     * directly in the sqlite_master table and recreate the index.
     */
    public function up(): void
    {
        // For SQLite: update the CREATE TABLE statement stored in sqlite_master
        // to expand the status CHECK constraint to include 'pending_photo_review'.
        $connection = DB::connection()->getDriverName();

        if ($connection === 'sqlite') {
            // Read current DDL
            $ddl = DB::select("SELECT sql FROM sqlite_master WHERE type='table' AND name='fuel_prices'");
            if (!empty($ddl)) {
                $sql = $ddl[0]->sql;

                // Replace the old enum/check constraint with the expanded one
                $oldCheck = "'crowdsourced', 'merchant_verified'";
                $newCheck = "'crowdsourced', 'merchant_verified', 'pending_photo_review'";

                if (str_contains($sql, $oldCheck)) {
                    $newSql = str_replace($oldCheck, $newCheck, $sql);

                    DB::statement('PRAGMA foreign_keys = OFF');
                    DB::statement('PRAGMA legacy_alter_table = ON');
                    DB::statement('ALTER TABLE fuel_prices RENAME TO fuel_prices_old');
                    DB::statement($newSql);
                    DB::statement('INSERT INTO fuel_prices SELECT * FROM fuel_prices_old');
                    DB::statement('DROP TABLE fuel_prices_old');
                    DB::statement('PRAGMA legacy_alter_table = OFF');
                    DB::statement('PRAGMA foreign_keys = ON');
                } else {
                    // Constraint text not found in expected format — just run a raw update
                    DB::statement('PRAGMA foreign_keys = OFF');
                    DB::statement('PRAGMA legacy_alter_table = ON');
                    DB::statement('ALTER TABLE fuel_prices RENAME TO fuel_prices_old');
                    DB::statement("
                        CREATE TABLE fuel_prices (
                            id TEXT NOT NULL PRIMARY KEY,
                            batch_id TEXT NULL,
                            station_id TEXT NOT NULL,
                            fuel_type TEXT CHECK(fuel_type IN ('regular unleaded (91)', 'premium unleaded(95)', 'regular diesel', 'premium diesel')) NOT NULL,
                            price NUMERIC(5,2) NOT NULL,
                            reported_by TEXT NOT NULL,
                            status TEXT CHECK(status IN ('crowdsourced', 'merchant_verified', 'pending_photo_review')) NOT NULL DEFAULT 'crowdsourced',
                            created_at DATETIME NULL,
                            updated_at DATETIME NULL,
                            image_path TEXT NULL,
                            ocr_verified INTEGER NOT NULL DEFAULT 0,
                            is_inside_geofence INTEGER NOT NULL DEFAULT 0,
                            FOREIGN KEY (station_id) REFERENCES gas_stations(id) ON DELETE CASCADE,
                            FOREIGN KEY (reported_by) REFERENCES users(id) ON DELETE CASCADE
                        )
                    ");
                    DB::statement('INSERT INTO fuel_prices SELECT * FROM fuel_prices_old');
                    DB::statement('DROP TABLE fuel_prices_old');
                    DB::statement('PRAGMA legacy_alter_table = OFF');
                    DB::statement('PRAGMA foreign_keys = ON');
                }
            }
        } else {
            // MySQL / PostgreSQL: straightforward MODIFY COLUMN
            DB::statement("ALTER TABLE fuel_prices MODIFY COLUMN status ENUM('crowdsourced', 'merchant_verified', 'pending_photo_review') NOT NULL DEFAULT 'crowdsourced'");
        }
    }

    public function down(): void
    {
        // Revert: remove pending_photo_review (convert any back to crowdsourced first)
        DB::table('fuel_prices')
            ->where('status', 'pending_photo_review')
            ->update(['status' => 'crowdsourced']);

        $connection = DB::connection()->getDriverName();
        if ($connection !== 'sqlite') {
            DB::statement("ALTER TABLE fuel_prices MODIFY COLUMN status ENUM('crowdsourced', 'merchant_verified') NOT NULL DEFAULT 'crowdsourced'");
        }
    }
};
