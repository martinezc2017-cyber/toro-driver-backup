# Reinstalar driver app con logs detallados
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "REINSTALANDO DRIVER APP CON LOGS DETALLADOS" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

cd "c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro driver flutter\toro_driver"

Write-Host "🔨 Hot restarting Flutter app..." -ForegroundColor Yellow
flutter run -d emulator-5554

Write-Host ""
Write-Host "===========================================" -ForegroundColor Green
Write-Host "APP INSTALADA - Ahora presiona los botones" -ForegroundColor Green
Write-Host "y copia TODOS los logs que aparezcan" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
