@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install.ps1"
set "TabLinkExit=%errorlevel%"
echo.
pause
exit /b %TabLinkExit%
