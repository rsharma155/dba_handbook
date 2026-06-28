@echo off
setlocal
set "HERE=%~dp0"
set "PORT=8742"

if exist "%HERE%dba-connector-1.0.0.jar" (
  set "ROOT=%HERE%"
  set "JAR=%HERE%dba-connector-1.0.0.jar"
) else (
  set "ROOT=%HERE%.."
  set "JAR=%ROOT%\unified_console\connector\target\dba-connector-1.0.0.jar"
)

if exist "%HERE%runtime\bin\java.exe" (
  set "JAVA=%HERE%runtime\bin\java.exe"
) else if exist "%ROOT%\unified_console\dist\DBA-Console-Portable\runtime\bin\java.exe" (
  set "JAVA=%ROOT%\unified_console\dist\DBA-Console-Portable\runtime\bin\java.exe"
) else (
  where java >nul 2>&1
  if errorlevel 1 (
    echo Java not found. Run build-portable.sh or install JDK 21+.
    pause
    exit /b 1
  )
  set "JAVA=java"
)

if not exist "%JAR%" (
  echo Connector JAR not found: %JAR%
  echo Build: mvn -f unified_console\connector\pom.xml package
  pause
  exit /b 1
)

cd /d "%ROOT%"
start "DBA Connector" "%JAVA%" -jar "%JAR%" --port %PORT%
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:%PORT%/"
echo DBA Console: http://127.0.0.1:%PORT%/
