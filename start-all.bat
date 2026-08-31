@echo off
echo Starting RoutePump Entire Suite (Backend + Admin Portal + Mobile App)...
echo.
echo 1. Starting Laravel API Backend on http://0.0.0.0:8000 ...
start "RoutePump Backend" cmd /k "cd /d "%~dp0backend" && php artisan serve --host 0.0.0.0 --port 8000"

echo 2. Starting Vite Admin Web Portal on http://localhost:5173 ...
start "RoutePump Admin" cmd /k "cd /d "%~dp0admin" && npm run dev"

echo 3. Launching Flutter Mobile Application...
start "RoutePump Mobile" cmd /k "cd /d "%~dp0mobile" && flutter run"

echo.
echo All RoutePump services started!
