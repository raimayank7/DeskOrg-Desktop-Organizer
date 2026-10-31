@echo off
setlocal
cd /d "%~dp0"

REM ==================================================
REM DeskOrg - re-sign helper (run after editing any script)
REM Credits: Nivesh Sahayak | https://niveshsahayak.in
REM ==================================================

if not exist "Resign-DeskOrg.ps1" (
    echo Resign-DeskOrg.ps1 was not found.
    pause
    exit /b 1
)

REM Maintenance action, run by the owner; Bypass lets it run even when the
REM helper itself has not yet been re-signed.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Resign-DeskOrg.ps1"

endlocal
