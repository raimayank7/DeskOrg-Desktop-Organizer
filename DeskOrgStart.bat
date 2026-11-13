@echo off
rem DeskOrg launcher. Designed & Developed by: Nivesh Sahayak - https://www.niveshsahayak.in
rem Starts DeskOrg without any console window (conhost --headless).
rem A 32-bit parent (such as an installer) cannot see the 64-bit System32 folder, but it can
rem reach the 64-bit conhost.exe through "Sysnative"; the 64-bit conhost then finds PowerShell
rem under the normal System32 path.
set "CH=%SystemRoot%\System32\conhost.exe"
if exist "%SystemRoot%\Sysnative\conhost.exe" set "CH=%SystemRoot%\Sysnative\conhost.exe"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
start "" "%CH%" --headless "%PS%" -NoLogo -NoProfile -STA -ExecutionPolicy AllSigned -File "%~dp0DeskOrgSplash.ps1"
