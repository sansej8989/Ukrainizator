@echo off
cd /d "%~dp0"
title Ukrainizator - Manual

:: Auto elevate to admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ukrainizator.ps1" %*
pause