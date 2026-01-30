@echo off
REM ============================================================
REM TORO DRIVER - Emulador Optimizado para Mapbox 3D Navigation
REM ============================================================

REM === CONFIGURACION (AJUSTAR SI ES NECESARIO) ===
set EMULATOR_PATH=C:\Users\marti\AppData\Local\Android\Sdk\emulator\emulator.exe
set AVD_NAME=Pixel_2

echo.
echo ========================================
echo   TORO DRIVER - Emulador Optimizado
echo ========================================
echo.

echo [1/3] Verificando emulador...
if not exist "%EMULATOR_PATH%" (
    echo.
    echo [ERROR] No se encontro el emulador en:
    echo         %EMULATOR_PATH%
    echo.
    echo Verifica la ruta de tu Android SDK
    pause
    exit /b 1
)
echo       [OK] Emulador encontrado

echo.
echo [2/3] Optimizaciones GPU para Mapbox:
echo       [x] GPU host (aceleracion hardware maxima)
echo       [x] 4GB RAM
echo       [x] 4 CPU cores
echo       [x] Boot limpio (sin cache corrupto)
echo       [x] Sin animacion de boot

echo.
echo [3/3] Lanzando emulador...
echo.
echo ========================================
echo   Espera 1-2 minutos para boot completo
echo   Luego en otra terminal: flutter run
echo ========================================
echo.

"%EMULATOR_PATH%" -avd %AVD_NAME% ^
    -gpu host ^
    -memory 4096 ^
    -cores 4 ^
    -no-snapshot-load ^
    -no-boot-anim

echo.
echo Emulador cerrado.
pause
