@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0list-models.ps1" %*
