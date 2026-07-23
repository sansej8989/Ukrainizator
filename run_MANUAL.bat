@echo off
title Ukrainizator - MANUAL mode

:: --- Check for admin rights, self-elevate if needed ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator rights required. Requesting elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================================
echo   UKRAINIZATOR - manual (interactive) mode
echo   The script will ask for confirmation at key steps
echo   (install mode, reboot, etc).
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ukrainizator.ps1"

echo.
echo Script finished.
pause