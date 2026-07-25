@echo off
REM Lives in scripts\ - the solution is one level up at the install root.
cd /d "%~dp0.."
dotnet test "%~dp0..\SqlOptima.SchemaCompare.sln" -c Release
if errorlevel 1 (
  echo.
  echo TESTS FAILED
  pause
  exit /b 1
)
echo.
echo All tests passed.
pause
