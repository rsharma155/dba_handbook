@echo off
REM Launch the SQL Optima Schema Compare desktop application
REM Lives in scripts\ - project folders are one level up at the install root.
set "ROOT=%~dp0.."
cd /d "%ROOT%"

set "EXE=%ROOT%\SqlOptima.SchemaCompare\bin\Release\net8.0-windows\SqlOptima.SchemaCompare.exe"
if not exist "%EXE%" set "EXE=%ROOT%\SqlOptima.SchemaCompare\bin\Debug\net8.0-windows\SqlOptima.SchemaCompare.exe"

if not exist "%EXE%" (
  echo Building desktop app first...
  dotnet build "%ROOT%\SqlOptima.SchemaCompare\SqlOptima.SchemaCompare.csproj" -c Release
  set "EXE=%ROOT%\SqlOptima.SchemaCompare\bin\Release\net8.0-windows\SqlOptima.SchemaCompare.exe"
)

if not exist "%EXE%" (
  echo ERROR: Could not find or build SqlOptima.SchemaCompare.exe
  echo Install .NET 8 SDK from https://dotnet.microsoft.com/download
  pause
  exit /b 1
)

start "" "%EXE%"
