<#
.SYNOPSIS
    Starts the DBA Handbook SQL Console - one command to run everything.

.DESCRIPTION
    Launches the SQL API server and opens the DBA Handbook HTML.
    Enter server details in the HTML, click Connect, and run queries.

    Press Ctrl+C in this window to stop the server.

.PARAMETER Port
    Port for the local API server. Default: 8742.

.EXAMPLE
    .\Start-SqlApiServer.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 8742
)

#Requires -Modules dbatools
#Requires -Version 5.1

$ErrorActionPreference = 'Continue'
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) { $scriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent }

$htmlPath = Join-Path (Split-Path $scriptRoot -Parent) 'output\DBA_Production_Handbook.html'
if (-not (Test-Path $htmlPath)) {
    Write-Host "Generating handbook HTML..." -ForegroundColor Cyan
    & (Join-Path $scriptRoot 'Generate-DBAHandbook.ps1')
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:${Port}/")
$listener.Start()

Write-Host ""
Write-Host "  DBA Handbook SQL Console" -ForegroundColor Cyan
Write-Host "  Server running at http://localhost:${Port}/" -ForegroundColor Green
Write-Host "  Opening handbook in browser..." -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

Start-Process $htmlPath

$connectedServers = @{}

function Send-Json {
    param($Context, $Data, [int]$Code = 200)
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $Code
    $Context.Response.ContentType = 'application/json'
    $Context.Response.ContentLength64 = $buf.Length
    $Context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Context.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $Context.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $Context.Response.OutputStream.Write($buf, 0, $buf.Length)
    $Context.Response.Close()
}

function Read-Body($Context) {
    $r = [System.IO.StreamReader]::new($Context.Request.InputStream)
    $b = $r.ReadToEnd(); $r.Close(); $b
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        $method = $ctx.Request.HttpMethod

        if ($method -eq 'OPTIONS') { Send-Json $ctx @{ ok = $true }; continue }

        try {
            switch ($path) {

                '/api/ping' { Send-Json $ctx @{ pong = $true } }

                '/api/health' {
                    Send-Json $ctx @{
                        status = 'running'
                        time = (Get-Date).ToString('o')
                        servers = @($connectedServers.Keys)
                    }
                }

                '/api/connect' {
                    $body = (Read-Body $ctx) | ConvertFrom-Json
                    $inst = $body.instance
                    $trustCert = if ($null -ne $body.trustCertificate) { $body.trustCertificate } else { $true }

                    $p = @{ SqlInstance = $inst; TrustServerCertificate = $trustCert }
                    if ($body.authType -eq 'SQL' -and $body.username) {
                        $sec = ConvertTo-SecureString $body.password -AsPlainText -Force
                        $p.Credential = [PSCredential]::new($body.username, $sec)
                    }

                    $server = Connect-DbaInstance @p
                    $info = @{ name = $server.Name; edition = $server.Edition; version = $server.VersionString; productLevel = $server.ProductLevel }
                    $connectedServers[$inst] = @{ server = $server; info = $info }

                    Send-Json $ctx @{ success = $true; server = $info }
                    Write-Host "  Connected: $inst" -ForegroundColor Green
                }

                '/api/disconnect' {
                    $body = (Read-Body $ctx) | ConvertFrom-Json
                    if ($connectedServers.ContainsKey($body.instance)) {
                        try { Disconnect-DbaInstance -SqlInstance $connectedServers[$body.instance].server -ErrorAction SilentlyContinue } catch {}
                        $connectedServers.Remove($body.instance)
                    }
                    Send-Json $ctx @{ success = $true }
                }

                '/api/databases' {
                    $body = (Read-Body $ctx) | ConvertFrom-Json
                    if (-not $connectedServers.ContainsKey($body.instance)) {
                        Send-Json $ctx @{ success = $false; error = "Not connected" } 400; continue
                    }
                    $ds = Invoke-DbaQuery -SqlInstance $connectedServers[$body.instance].server -Database 'master' `
                        -Query "SELECT name, database_id, state_desc, recovery_model_desc FROM sys.databases ORDER BY name" -As DataSet
                    $dbs = @()
                    foreach ($r in $ds.Tables[0].Rows) {
                        $dbs += @{ name = $r['name']; id = $r['database_id']; state = $r['state_desc']; recovery = $r['recovery_model_desc'] }
                    }
                    Send-Json $ctx @{ success = $true; databases = $dbs }
                }

                '/api/execute' {
                    $body = (Read-Body $ctx) | ConvertFrom-Json
                    $inst = $body.instance
                    $query = $body.query
                    $db = if ($body.database) { $body.database } else { 'master' }

                    if (-not $connectedServers.ContainsKey($inst)) {
                        Send-Json $ctx @{ success = $false; error = "Not connected to $inst" } 400; continue
                    }

                    $sw = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        $ds = Invoke-DbaQuery -SqlInstance $connectedServers[$inst].server -Database $db -Query $query -As DataSet
                        $sw.Stop()

                        $tables = @()
                        foreach ($dt in $ds.Tables) {
                            $rows = @()
                            foreach ($row in $dt.Rows) {
                                $rd = @{}
                                foreach ($col in $dt.Columns) {
                                    $v = $row[$col.ColumnName]
                                    if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm:ss') }
                                    elseif ($v -is [decimal]) { $v = [double]$v }
                                    $rd[$col.ColumnName] = $v
                                }
                                $rows += $rd
                            }
                            $tables += @{
                                columns = @($dt.Columns | ForEach-Object { @{ name = $_.ColumnName; type = $_.DataType.Name } })
                                rows = $rows; rowCount = $dt.Rows.Count
                            }
                        }
                        Send-Json $ctx @{ success = $true; tables = $tables; durationMs = $sw.ElapsedMilliseconds; tableCount = $tables.Count }
                        Write-Host "  Query: $($sw.ElapsedMilliseconds)ms, $($tables.Count) result set(s)" -ForegroundColor Gray
                    }
                    catch {
                        $sw.Stop()
                        Send-Json $ctx @{ success = $false; error = $_.Exception.Message; durationMs = $sw.ElapsedMilliseconds } 400
                        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }

                default { Send-Json $ctx @{ error = "Unknown endpoint" } 404 }
            }
        }
        catch {
            try { Send-Json $ctx @{ success = $false; error = $_.Exception.Message } 500 } catch {}
        }
    }
}
finally {
    Write-Host "`nShutting down..." -ForegroundColor Yellow
    foreach ($k in $connectedServers.Keys) {
        try { Disconnect-DbaInstance -SqlInstance $connectedServers[$k].server -ErrorAction SilentlyContinue } catch {}
    }
    $listener.Stop(); $listener.Close()
}
