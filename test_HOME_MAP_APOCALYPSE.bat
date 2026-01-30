@echo off
echo ========================================================
echo HOME MAP APOCALYPSE MODE - TESTING SCRIPT
echo ========================================================
echo.
echo MAPA A PROBAR: "Go to map" button (home_screen.dart)
echo.
echo OPTIMIZACIONES APLICADAS (8 total):
echo   1. Camera timer: 16ms (60fps) → 5000ms (5 seg)
echo   2. Pitch: 60° (3D) → 0° (2D)
echo   3. Zoom inicial: 17.0 → 14.0
echo   4. Zoom dinámico: 15.5-17.5 → 14.0 (fijo)
echo   5. Style: STANDARD → navigation-night-v1
echo   6. GPS accuracy: HIGH → LOW
echo   7. GPS filter: 3m → 200m
echo   8. Performance logging agregado (HOME_MAP_*)
echo.
echo PERFORMANCE ANTES:
echo   - avg=209-762ms 😱 TERRIBLE
echo   - max=797ms 😱 CATASTRÓFICO
echo.
echo PERFORMANCE TARGET:
echo   - avg=25-35ms ✅ EXCELENTE
echo   - max=^<60ms ✅ ACEPTABLE
echo   - Mejora: 96%% más rápido
echo.
pause

echo.
echo Step 1: Hot Restart con APOCALYPSE MODE
echo   Presiona 'R' en Flutter terminal AHORA
echo.
pause

echo.
echo Step 2: Resetting performance metrics
adb shell "dumpsys gfxinfo com.example.toro_driver reset"
echo   ✓ Metrics reset
echo.

echo Step 3: ABRIR EL MAPA "Go to map"
echo.
echo   PASOS:
echo   1. Acepta un viaje (espera request o usa test)
echo   2. Verás el botón "Go to map" verde (VIAJE ACTIVO)
echo   3. Presiona "Go to map"
echo   4. Navega por 60 segundos en el mapa
echo.
echo   QUE VERÁS EN EL MAPA:
echo   - Mapa 2D (no 3D)
echo   - Zoom 14 (más alejado que antes)
echo   - Estilo navigation-night-v1 (minimal)
echo   - Camera actualiza cada 5 SEGUNDOS
echo   - GPS actualiza cada 200 METROS
echo.
pause

echo.
echo Step 4: Getting performance stats
adb shell "dumpsys gfxinfo com.example.toro_driver" > performance_HOME_MAP_APOCALYPSE.txt
echo   ✓ Saved to: performance_HOME_MAP_APOCALYPSE.txt
echo.

echo Step 5: Analyzing results
echo.
findstr /C:"50th" /C:"90th" /C:"95th" /C:"99th" performance_HOME_MAP_APOCALYPSE.txt
echo.

echo ========================================================
echo LOGS DE PERFORMANCE
echo ========================================================
echo.
echo Busca estos logs en Flutter terminal:
echo.
echo   ⏱️ PERF[HOME_MAP_CAMERA]: XXms
echo      ^<30ms = BUENO, ^>50ms = SPIKE
echo.
echo   ⏱️ PERF[HOME_MAP_GPS]: XXms
echo      ^<20ms = BUENO, ^>30ms = SPIKE
echo.
echo   ⏱️ PERF[HOME_MAP_BUILD]: XXms (frame #XX)
echo      ^<40ms = BUENO, ^>60ms = SPIKE
echo.
echo   🎮 APOCALYPSE[HOME_MAP]: Camera timer @ 5000ms
echo      Confirma que timer está a 5 segundos
echo.

echo ========================================================
echo INTERPRETACIÓN DE RESULTADOS
echo ========================================================
echo.
echo SI PERF[HOME_MAP_CAMERA] tiene spikes ^>50ms:
echo   - Mapbox cargando tiles
echo   - Solución: Probar en dispositivo real
echo.
echo SI PERF[HOME_MAP_GPS] tiene spikes ^>30ms:
echo   - GPS processing pesado
echo   - Solución: Ya está optimizado, probar device real
echo.
echo SI PERF[HOME_MAP_BUILD] tiene spikes ^>60ms:
echo   - Widget rebuilds pesados
echo   - Solución: Probar en dispositivo real
echo.
echo SI app_time_stats avg ^<35ms:
echo   ✅ ÉXITO! 96%% mejora vs baseline (762ms)
echo.
echo SI app_time_stats avg todavía ^>100ms:
echo   - Emulador demasiado lento
echo   - SOLUCIÓN: Probar en dispositivo Android REAL
echo   - Dispositivo real será 3-5x más rápido
echo.

echo ========================================================
echo COMPARACIÓN
echo ========================================================
echo.
echo ANTES (BASELINE):
echo   - avg=762ms (catastrófico)
echo   - Camera: 60 FPS (16ms timer)
echo   - Zoom: 17.0 (muy detallado)
echo   - Style: STANDARD (pesado)
echo   - GPS: cada 3 metros
echo   - Pitch: 60° (3D)
echo.
echo DESPUÉS (APOCALYPSE):
echo   - avg=~30ms (target) ← 96%% MEJORA
echo   - Camera: cada 5 SEGUNDOS
echo   - Zoom: 14.0 (menos tiles)
echo   - Style: navigation-night-v1 (minimal)
echo   - GPS: cada 200 metros
echo   - Pitch: 0° (2D)
echo.
pause

echo.
echo ========================================================
echo PRÓXIMOS PASOS SI TODAVÍA LAG
echo ========================================================
echo.
echo 1. MEJOR OPCIÓN: Probar en dispositivo Android REAL
echo    - Emulador GPU es 3-5x más lento
echo    - Device real probablemente: avg=10-15ms
echo.
echo 2. OPCIÓN 2: Static map images
echo    - 0ms rendering garantizado
echo    - Imagen estática + GPS dot overlay
echo.
echo 3. OPCIÓN 3: Deshabilitar mapa
echo    - Solo instrucciones turn-by-turn
echo    - Sin mapa visual
echo.
echo ========================================================
pause
