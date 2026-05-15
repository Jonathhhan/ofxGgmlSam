@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-sam3-runtime-smoke.ps1" %*
