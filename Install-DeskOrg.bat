@echo off
setlocal
cd /d "%~dp0"

REM ==================================================
REM DeskOrg - run this ONCE on a new PC to set it up
REM Credits: Nivesh Sahayak | https://niveshsahayak.in
REM ==================================================

if not exist "Install-DeskOrg.ps1" (
    echo Install-DeskOrg.ps1 was not found.
    echo Make sure you copied the ENTIRE DeskOrg folder, not just DeskOrg.exe.
    pause
    exit /b 1
)

REM Bypass is required here: on a brand-new PC the certificate is not trusted
REM yet, so this setup script must be allowed to run in order to install trust.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DeskOrg.ps1"

endlocal
