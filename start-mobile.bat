@echo off
echo Starting RoutePump Backend and Mobile Application...
echo.
echo 1. Starting Laravel Backend on http://0.0.0.0:8000 ...
start "RoutePump Backend" cmd /k "cd /d "%~dp0backend" && php artisan serve --host 0.0.0.0 --port 8000"

echo 2. Launching Flutter Mobile Application...
start "RoutePump Mobile" cmd /k "cd /d "%~dp0mobile" && flutter run"

echo.
echo Both components launched!
echo If offline, the mobile app will automatically fallback to Sandbox Mode.
