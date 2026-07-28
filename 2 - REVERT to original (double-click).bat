@echo off
title EQ NAG - revert patch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0revert-nag.ps1"
echo.
pause
