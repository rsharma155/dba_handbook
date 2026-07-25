@echo off
REM Double-click launcher for Schema Compare GUI (STA apartment required for WinForms)
cd /d "%~dp0"
title SQL Schema Compare GUI
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Start-SchemaCompareGui.ps1"
if errorlevel 1 (
  echo.
  echo The GUI exited with an error. See messages above.
  pause
)
