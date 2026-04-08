@echo off
:: Check for administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Restarting the batch file with administrator privileges...
    powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit
)

REM If running as administrator, launch the PowerShell script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Shelenko\main\install languges 3\install languges.ps1"
pause
