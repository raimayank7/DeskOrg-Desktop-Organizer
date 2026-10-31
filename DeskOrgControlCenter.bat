
@echo off
setlocal
cd /d "%~dp0"

if not exist "DeskOrgControlCenter.ps1" (
    echo DeskOrgControlCenter.ps1 was not found.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy AllSigned -File "%~dp0DeskOrgControlCenter.ps1"

endlocal
