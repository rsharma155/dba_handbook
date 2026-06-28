# Unified DBA Console (native Go)

Single native binary — **no Java, no JAR, no `runtime/` folder**.

Connect to **SQL Server** or **PostgreSQL**, browse 125+ embedded scripts, run them from the browser UI.

## End user

### Windows

1. Unzip `dist/DBA-Console-Portable-Windows.zip` (~12 MB)
2. Double-click **`DBA-Console.exe`**
3. Browser opens → connect → run scripts

### macOS

1. Unzip `dist/DBA-Console-Portable-Mac.zip`
2. Double-click **`DBA-Console`**
3. If blocked: right-click → **Open** → **Open**

### Portable folder contents

```
DBA-Console-Portable-Windows/
├── DBA-Console.exe      ~12 MB (connector + launcher + SQL drivers)
└── DBA_Console.html     ~0.6 MB (UI + embedded scripts)
```

Total: **~13 MB** (was ~150 MB with Java runtime).

## Build (maintainers)

Requirements: **Go 1.22+**, Python 3 (embed scripts only)

```bash
./unified_console/scripts/assemble-portable.sh
```

Or step by step:

```bash
python3 unified_console/shell/build_console.py
./unified_console/scripts/build.sh
```

Output zips in `unified_console/dist/`.

## Windows code signing (SmartScreen)

Unsigned executables may show **Windows protected your PC**. Signing requires **your** Authenticode certificate (not something we can generate in the repo).

On a Windows build machine with a `.pfx` certificate:

```powershell
$env:DBA_SIGN_PFX = "C:\path\to\cert.pfx"
$env:DBA_SIGN_PFX_PASSWORD = "your-password"
.\unified_console\scripts\sign-windows.ps1 -ExePath .\unified_console\dist\DBA-Console.exe
```

Or with a certificate in the Windows store:

```powershell
$env:DBA_SIGN_THUMBPRINT = "YOUR_CERT_SHA1_THUMBPRINT"
.\unified_console\scripts\sign-windows.ps1 -ExePath .\unified_console\dist\DBA-Console.exe
```

`assemble-portable.sh` calls `sign-windows.ps1` automatically on Windows when these variables are set.

**Note:** Self-signed certificates do **not** remove SmartScreen. You need a trusted code signing cert (often EV for immediate reputation).

## Architecture

```
DBA-Console.exe / DBA-Console
├── HTTP API on 127.0.0.1:8742
├── Serves DBA_Console.html
├── github.com/microsoft/go-mssqldb  (SQL Server)
└── github.com/jackc/pgx/v5          (PostgreSQL)
```

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/ping` | GET | Health check |
| `/api/connect` | POST | Connect to database |
| `/api/disconnect` | POST | Close connection |
| `/api/execute` | POST | Run SQL |

## Deprecated

- `connector/` — Java JAR connector (replaced by Go)
- `launcher/` — old JAR launcher
- `connection_libraries/` — JDBC jars (drivers compiled into Go binary)
