@echo off
echo ================================================
echo TESTING EXTREME MODE OPTIMIZATIONS
echo ================================================
echo.
echo CHANGES APPLIED:
echo   1. Route polyline DISABLED (blue line removed)
echo   2. Bearing rotation DISABLED (always north-up)
echo   3. Zoom reduced: 17.5 -^> 16.0
echo   4. GPS filter: 30m -^> 50m
echo.
echo BEFORE OPTIMIZATION:
echo   Average: 30-50ms
echo   Worst spikes: 85-114ms ^<-- TERRIBLE
echo.
echo TARGET AFTER OPTIMIZATION:
echo   Average: 25-35ms
echo   Worst spikes: ^<50ms
echo.
pause

echo.
echo Step 1: Hot Restarting app...
echo   Press 'R' in your Flutter terminal
echo.
pause

echo.
echo Step 2: Resetting performance metrics...
adb shell "dumpsys gfxinfo com.example.toro_driver reset"
echo   ✓ Metrics reset
echo.

echo Step 3: TEST NAVIGATION NOW
echo   - Accept a ride
echo   - Press LLEGUE button
echo   - Navigate for 30-60 seconds
echo   - NOTE: No blue route line (disabled for performance)
echo   - NOTE: Map always north-up (no rotation)
echo.
pause

echo.
echo Step 4: Getting performance stats...
adb shell "dumpsys gfxinfo com.example.toro_driver" > performance_EXTREME_MODE.txt
echo   ✓ Saved to: performance_EXTREME_MODE.txt
echo.

echo Step 5: Analyzing results...
echo.
findstr /C:"50th" /C:"90th" /C:"95th" /C:"99th" performance_EXTREME_MODE.txt
echo.

echo ================================================
echo ANALYSIS:
echo   - If 90th percentile ^< 50ms: SUCCESS ✓
echo   - If 90th percentile 50-60ms: Acceptable
echo   - If 90th percentile ^> 60ms: Still laggy, consider static map
echo.
echo See: EXTREME_MODE_OPTIMIZATIONS.md for details
echo ================================================
pause
