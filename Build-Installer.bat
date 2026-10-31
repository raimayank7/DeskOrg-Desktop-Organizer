@echo off
setlocal
cd /d "%~dp0"

REM ==================================================
REM DeskOrg - rebuild EXE + re-sign + build installer
REM Credits: Nivesh Sahayak | https://niveshsahayak.in
REM ==================================================

if not exist "Build-Installer.ps1" (
    echo Build-Installer.ps1 was not found.
    pause
    exit /b 1
)

REM Owner maintenance action; Bypass so it runs regardless of signing state.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Installer.ps1"

endlocal
