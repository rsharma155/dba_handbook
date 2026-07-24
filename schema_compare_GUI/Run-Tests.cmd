@echo off
cd /d "%~dp0"
dotnet test "%~dp0SqlOptima.SchemaCompare.sln" -c Release
if errorlevel 1 (
  echo.
  echo TESTS FAILED
  pause
  exit /b 1
)
echo.
echo All tests passed.
pause
