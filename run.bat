@echo off
chcp 65001 > nul
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ukrainizator.ps1"
pause