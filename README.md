# RoutePump: Smart Fuel Routing and Participatory Queue Estimation

RoutePump is a GIS-powered system that optimizes vehicle fuel replenishment routing by calculating detour distances, traffic conditions, and gas station queue times. It comprises a Laravel PHP API backend, a Vite-based Admin Web Portal, and a Flutter Mobile Application.

---

## System Requirements
- **PHP** (>= 8.1) & **Composer**
- **Node.js** (>= 18) & **NPM**
- **Flutter SDK** (channel stable)

---

## Step 1: Initialize the Database (Laravel Backend)

If you are getting a **"Bad credentials"** error, it means the SQLite database needs to be migrated and seeded with the default accounts and stations. 

Open a terminal at `c:\it22\RoutePump\backend` and run:

```bash
# 1. Navigate to the backend directory
cd backend

# 2. Run fresh database migrations (creates SQLite tables)
php artisan migrate:fresh

# 3. Seed the database with default admin, motorist, and partner accounts
php artisan db:seed
```

### Seeded Credentials:
- **System Administrator (Web App)**:
  - Email: `admin@routepump.com`
  - Password: `password`
- **Standard Motorist (Mobile App)**:
  - Email: `motorist@routepump.com`
  - Password: `password`
- **Petron Roxas Branch Partner Employee (Mobile App)**:
  - Email: `partner@routepump.com`
  - Password: `password`

---

## Step 2: Running the Components

You will need to open **three separate terminals** to run each component of the system simultaneously.

### Terminal A: Laravel API Backend
To serve the API so it is accessible from both your browser (for the Web Admin) and a physical device (over local Wi-Fi), bind it to all host interfaces:
```bash
cd backend
php artisan serve --host 0.0.0.0 --port 8000
```
> [!NOTE]
> The API server is served at `http://192.168.254.110:8000` (your computer's local network IP) or `http://localhost:8000`.

### Terminal B: Vite Admin Web Portal
Run the admin web portal locally:
```bash
cd admin
npm run dev
```
- Open the printed URL (usually `http://localhost:5173`) in your browser.
- Log in using the **Admin** credentials: `admin@routepump.com` / `password`.
- **Feature Check**: Click on the map to automatically draw geofence polygons, approve/dismiss price reports, and use the **Telemetry Sim** panel to mock motorists in queues.

### Terminal C: Flutter Mobile Application
Connect your physical device (Android with USB Debugging enabled) or open an emulator, then execute:
```bash
cd mobile
flutter run
```
- Log in as the **Motorist** (`motorist@routepump.com`) or the **Partner Employee** (`partner@routepump.com`).
- **Feature Check**: Drag your location dot on the Map tab to dynamically update optimized net detour savings, configure vehicle profiles, or report crowdsourced pricing inside station geofences.

---

## Network Debugging Tip (Real Devices)
If your phone is running the app and cannot connect to the backend:
1. Double-check that your computer and phone are connected to the **same Wi-Fi router**.
2. Make sure Windows Firewall is not blocking port `8000`. You can allow port `8000` or temporarily turn off firewall restrictions on private networks.
3. If your computer's IP address changes, update the `apiBaseUrl` constant in `mobile/lib/main.dart` (line 7).

---

## Algorithm & Core Calculations

RoutePump's routing engine is built around a **Net Financial Savings (S_net) algorithm** that replaces the standard travel-time/distance pathfinding cost function with a pure economic cost-benefit evaluation per candidate gas station.

---

### Equation 1 — Total Net Savings (S_net)

```
S_net = [ V_purchase × (P_baseline − P_target) ] − C_travel
```

| Variable      | Description                                                             |
|---------------|-------------------------------------------------------------------------|
| `S_net`       | Total net financial savings derived from the detour (₱)                 |
| `V_purchase`  | Intended fuel volume to purchase (Liters)                               |
| `P_baseline`  | Fuel price per liter at the **nearest** station on the driver's path (₱/L) |
| `P_target`    | Fuel price per liter at the cheaper, more distant target station (₱/L)  |
| `C_travel`    | Total cost of the detour trip (₱) — see Equation 2                     |

**Implementation:** `GasStationController.php` → `routing()` method
```php
$grossSavings = $liters * ($baselinePrice - $price);  // V_purchase × (P_baseline − P_target)
$netSavings   = $grossSavings - $cTravel;             // − C_travel
```

---

### Equation 2 — Detour Travel Cost (C_travel)

```
C_travel = (D / E × P_target) + (T_idle × R_idle × P_target)
```

| Variable    | Description                                                    |
|-------------|----------------------------------------------------------------|
| `D`         | Total detour distance to the selected target station (km)      |
| `E`         | Registered vehicle fuel efficiency (km/L)                      |
| `T_idle`    | Calculated queue wait time at the target station (hours)       |
| `R_idle`    | Fixed vehicle idling fuel consumption rate (L/hour)            |
| `P_target`  | Fuel price per liter at the target station (₱/L)               |

**Implementation:** `GasStationController.php` → `routing()` method
```php
$fuelBurnedDriving = $effectiveDist / $efficiency;        // D / E
$fuelBurnedIdling  = $tIdleHours * $idlingRate;           // T_idle × R_idle
$totalFuelBurned   = $fuelBurnedDriving + $fuelBurnedIdling;
$cTravel           = $totalFuelBurned * $price;           // × P_target
```

> **Real-world extensions applied to D:**
> The raw Haversine (straight-line) distance is adjusted by two multipliers before being used as `D`:
> - **Road curvature factor `× 1.3`** — accounts for the fact that roads are not perfectly straight.
> - **Traffic density factor `× 1.2` (normal) or `× 1.8` (rush hour)** — applied during detected rush hours: 7:30–9:00 AM and 5:00–6:30 PM.
>
> So: `D_effective = haversine_distance × 1.3 × trafficFactor`

---

### Equation 3 — Participatory Queue Estimation Q(t)

Station boundaries are mapped as discrete spatial polygons (Geofences). At a given time `t`, the current queue length `Q(t)` is computed dynamically from live user telemetry:

```
       N
Q(t) = Σ U_i(t)
      i=1

Where: U_i(t) = 1,  if Location_i(t) ∈ Geofence_station  AND  Velocity_i(t) ≈ 0
               0,  Otherwise
```

This filters out passive passersby driving alongside the station lot from active motorists idling in line.

**Implementation:** `GasStationController.php` → `calculateStationQueue()` method
```php
$queueCount = TelemetryLog::where('station_id', $stationId)
    ->where('is_inside_fence', true)   // Location_i ∈ Geofence_station
    ->where('velocity', '<', 5.0)      // Velocity_i ≈ 0  (practical idling threshold: < 5 km/h)
    ->where('timestamp', '>=', $fiveMinutesAgo)
    ->distinct('user_id')
    ->count('user_id');

$waitTimeHours = ($queueCount * 3.0) / 60.0;  // 3 minutes average service time per vehicle
```

The telemetry logging itself (`TelemetryController.php` → `log()`) uses a **Ray-Casting polygon algorithm** to determine whether a motorist's GPS coordinate falls inside a station's geofence polygon at the time of the report.

---

### Worked Example (Davao City)

A motorist intends to purchase **30 L** of fuel. Vehicle efficiency `E = 12.5 km/L`.

| Option   | Station Type        | Distance | Price (₱/L) |
|----------|---------------------|----------|-------------|
| Option A | Nearest (Baseline)  | 0 km     | ₱75.00      |
| Option B | Cheaper (Target)    | 5 km     | ₱71.00      |

**Step 1 — Gross Savings:**
```
30L × (₱75.00 − ₱71.00) = ₱120.00
```

**Step 2 — Travel Cost (zero-queue scenario):**
```
Fuel burned driving = 5 km ÷ 12.5 km/L = 0.4 L
C_travel = 0.4 L × ₱71.00 = ₱28.40
```

**Step 3 — Net Savings:**
```
S_net = ₱120.00 − ₱28.40 = ₱91.60  ✅ Route to Option B
```

If the queue at Option B generates an idle time `T_idle` whose fuel cost exceeds ₱91.60, the system automatically redirects the motorist back to Option A (or the next best station) to avoid a net loss.

---

### Decision Logic

The routing engine evaluates **all active stations**, computes `S_net` for each, sorts them **descending by `S_net`**, and recommends the station with the highest positive net savings. The nearest station is always treated as the baseline (`P_baseline`, `gross_savings = 0`). Stations with a negative `S_net` indicate that the detour costs more than it saves and are ranked last.
