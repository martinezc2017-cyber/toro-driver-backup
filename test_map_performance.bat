@echo off
echo ================================================
echo TESTING OPTIMIZED MAP PERFORMANCE
echo ================================================
echo.

echo 1. Hot Restarting Flutter app to apply optimizations...
echo    Press 'R' in the Flutter terminal or run:
echo    flutter run -d emulator-5554
echo.
pause

echo.
echo 2. Resetting performance metrics...
adb shell "dumpsys gfxinfo com.example.toro_driver reset"
echo    ✓ Metrics reset
echo.

echo 3. NOW:
echo    - Accept a ride in the driver app
echo    - Press "LLEGUE" button
echo    - Navigate for 30-60 seconds
echo    - Watch the map smoothness
echo.
pause

echo.
echo 4. Getting NEW performance stats...
adb shell "dumpsys gfxinfo com.example.toro_driver" > map_performance_AFTER.txt
echo    ✓ Stats saved to: map_performance_AFTER.txt
echo.

echo 5. Showing results...
echo.
findstr /C:"50th" /C:"90th" /C:"95th" /C:"99th" map_performance_AFTER.txt
echo.

echo ================================================
echo BEFORE OPTIMIZATIONS:
echo   50th percentile: 22ms
echo   90th percentile: 81ms  ^<-- TOO SLOW
echo.
echo TARGET (Google Maps level):
echo   50th percentile: ^<20ms
echo   90th percentile: ^<45ms
echo.
echo Check map_performance_AFTER.txt for full results
echo ================================================
pause
