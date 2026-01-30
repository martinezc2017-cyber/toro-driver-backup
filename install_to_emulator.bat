@echo off
REM Install Toro Driver to emulator

echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo    Installing TORO DRIVER to Emulator...
echo ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo.

echo 1. Checking emulator...
C:\Users\marti\AppData\Local\Android\Sdk\platform-tools\adb.exe devices

echo.
echo 2. Building and installing app...
C:\src\flutter\bin\flutter.bat run

echo.
pause
