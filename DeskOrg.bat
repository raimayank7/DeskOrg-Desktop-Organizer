@echo off
setlocal DisableDelayedExpansion

REM ==================================================
REM DeskOrg - Dynamic Desktop Organizer
REM Credits: Nivesh Sahayak
REM Website: https://niveshsahayak.in
REM ==================================================

set "SCRIPT=%~dp0DeskOrgOrganizer.ps1"

if not exist "%SCRIPT%" (
    echo ERROR: DeskOrgOrganizer.ps1 was not found.
    echo Expected location: "%SCRIPT%"
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy AllSigned -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"

if not "%RESULT%"=="0" (
    echo.
    echo DeskOrg encountered an error.
    echo Check the log at: "%TEMP%\DeskOrg.log"
)

exit /b %RESULT%