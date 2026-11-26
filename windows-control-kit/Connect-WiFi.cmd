@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-Control.ps1" -Mode WiFi
set "TabLinkExit=%errorlevel%"
exit /b %TabLinkExit%
