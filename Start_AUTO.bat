@echo off
title Ukrainizator - AUTO mode

:: --- Check for admin rights, self-elevate if needed ---
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Administrator rights required. Requesting elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo ============================================================
echo   UKRAINIZATOR - automatic (silent) mode
echo   No prompts, applies to all users, auto-reboots
echo   (with a 5-second window to cancel).
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ukrainizator.ps1" -Silent -Mode All -NoRebootPrompt

echo.
echo Script finished.
pause