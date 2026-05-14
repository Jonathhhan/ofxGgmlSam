@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%repair-point-example-vsproj.ps1" %*
exit /b %ERRORLEVEL%
