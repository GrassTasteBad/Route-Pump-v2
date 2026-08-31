#!/usr/bin/env pwsh
# RoutePump Dev Launcher
# Starts Laravel backend + Android emulator + Flutter app in one shot

$ROOT       = "c:\Users\PJ\Documents\UM LMS\CAPS 1\RoutePump-main"
$BACKEND    = "$ROOT\backend"
$MOBILE     = "$ROOT\mobile"
$ADB        = "C:\Users\PJ\AppData\Local\Android\sdk\platform-tools\adb.exe"
$EMULATOR   = "Pixel_9"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  RoutePump Dev Launcher" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Start Laravel backend in a new window ─────────────────────────────────
Write-Host "[1/4] Starting Laravel backend..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$BACKEND'; php artisan serve" -WindowStyle Normal
Start-Sleep -Seconds 2
Write-Host "      Backend starting at http://127.0.0.1:8000" -ForegroundColor Green

# ── 2. Restart ADB cleanly ───────────────────────────────────────────────────
Write-Host "[2/4] Restarting ADB..." -ForegroundColor Yellow
& $ADB kill-server 2>$null
Start-Sleep -Seconds 1
& $ADB start-server 2>$null
Start-Sleep -Seconds 1

# ── 3. Launch emulator if not already running ─────────────────────────────────
$devices = & $ADB devices 2>$null
if ($devices -notmatch "emulator") {
    Write-Host "[3/4] Launching $EMULATOR emulator..." -ForegroundColor Yellow
    Set-Location $MOBILE
    flutter emulators --launch $EMULATOR | Out-Null

    Write-Host "      Waiting for emulator to boot (this may take ~30s)..." -ForegroundColor DarkYellow
    $timeout = 120
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $boot = & $ADB -e shell getprop sys.boot_completed 2>$null
        if ($boot -eq "1") {
            Write-Host "      Emulator booted!" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 3
        $elapsed += 3
        Write-Host "      ...${elapsed}s" -ForegroundColor DarkGray
    }
    if ($elapsed -ge $timeout) {
        Write-Host "      Emulator boot timeout. Try opening Android Studio and booting manually." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[3/4] Emulator already running." -ForegroundColor Green
}

# ── 4. Run Flutter app ────────────────────────────────────────────────────────
Write-Host "[4/4] Launching RoutePump on emulator..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press 'r' to hot reload | 'R' to restart | 'q' to quit" -ForegroundColor Cyan
Write-Host ""
Set-Location $MOBILE
flutter run -d emulator-5554
