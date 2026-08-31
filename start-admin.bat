@echo off
echo Starting RoutePump Backend and Admin Portal...
start "RoutePump Backend" cmd /k "cd /d "%~dp0backend" && php artisan serve --host 0.0.0.0 --port 8000"
start "RoutePump Admin" cmd /k "cd /d "%~dp0admin" && npm run dev"
