function Export-AssessmentHtml {
    <#
    .SYNOPSIS
        Generates an HTML assessment report using PSWriteHTML.
    .PARAMETER ServerName
        SQL Server instance name.
    .PARAMETER HealthScore
        Overall health score (0-100).
    .PARAMETER TrafficLight
        GREEN, YELLOW, or RED.
    .PARAMETER Dashboard
        Dashboard metrics hashtable.
    .PARAMETER Findings
        Array of finding objects.
    .PARAMETER Sections
        Array of section collector results.
    .PARAMETER OutputPath
        Directory for the output file.
    #>
    [CmdletBinding()]
    param(
        [string]$ServerName,
        [int]$HealthScore,
        [string]$TrafficLight,
        [hashtable]$Dashboard,
        [array]$Findings,
        [array]$Sections,
        [string]$OutputPath
    )

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $safeServerName = $ServerName -replace '[\\\/\:\*\?\"\<\>\|]', '_'
    $fileName = "${safeServerName}_${timestamp}.html"
    $fullPath = Join-Path $OutputPath $fileName

    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    }

    $scoreColor = switch ($TrafficLight) {
        'GREEN'  { '#28a745' }
        'YELLOW' { '#ffc107' }
        'RED'    { '#dc3545' }
    }

    $finds = if ($Findings) { $Findings } else { @() }
    $criticalCount = @($finds | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
    $highCount = @($finds | Where-Object { $_.Severity -eq 'HIGH' }).Count
    $mediumCount = @($finds | Where-Object { $_.Severity -eq 'MEDIUM' }).Count
    $lowCount = @($finds | Where-Object { $_.Severity -eq 'LOW' }).Count

    $html = New-HTML -FilePath $fullPath -Title "SQL Optima Assessment - $ServerName" {
        New-HTMLHeader {
            New-HTMLPanel -Width '100%' {
                New-HTMLText -Text "SQL Optima DBA Assessment" -FontSize 24 -FontWeight bold -Color '#1a237e'
                New-HTMLText -Text "Server: $ServerName" -FontSize 16 -Color '#455a64'
                New-HTMLText -Text "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -FontSize 12 -FontStyle italic -Color '#78909c'
            }
        }

        New-HTMLMain {
            # KPI cards - Key Metrics row
            New-HTMLSection -Title 'Key Metrics' {
                New-HTMLPanel -Width '25%' -BackgroundColor $scoreColor {
                    New-HTMLText -Text "Health Score" -FontSize 14 -Color white
                    New-HTMLText -Text "$HealthScore / 100" -FontSize 36 -FontWeight bold -Color white
                    New-HTMLText -Text "Status: $TrafficLight" -FontSize 12 -Color white
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#1976d2' {
                    New-HTMLText -Text "SQL CPU" -FontSize 14 -Color white
                    New-HTMLText -Text "$($Dashboard.SQL_CPU_Pct)%" -FontSize 36 -FontWeight bold -Color white
                    New-HTMLText -Text "Process Utilization" -FontSize 12 -Color white
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#388e3c' {
                    New-HTMLText -Text "Signal Waits" -FontSize 14 -Color white
                    New-HTMLText -Text "$($Dashboard.Signal_Wait_Pct)%" -FontSize 36 -FontWeight bold -Color white
                    New-HTMLText -Text "of total wait time" -FontSize 12 -Color white
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#f57c00' {
                    New-HTMLText -Text "Page Life Expectancy" -FontSize 14 -Color white
                    New-HTMLText -Text "$($Dashboard.PLE_Seconds)s" -FontSize 36 -FontWeight bold -Color white
                    New-HTMLText -Text "Buffer pool health" -FontSize 12 -Color white
                }
            }

            New-HTMLSection -Title 'Findings Overview' {
                New-HTMLPanel -Width '25%' -BackgroundColor '#dc3545' {
                    New-HTMLText -Text "Critical" -FontSize 14 -Color white
                    New-HTMLText -Text $criticalCount -FontSize 36 -FontWeight bold -Color white
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#fd7e14' {
                    New-HTMLText -Text "High" -FontSize 14 -Color white
                    New-HTMLText -Text $highCount -FontSize 36 -FontWeight bold -Color white
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#ffc107' {
                    New-HTMLText -Text "Medium" -FontSize 14 -Color '#333'
                    New-HTMLText -Text $mediumCount -FontSize 36 -FontWeight bold -Color '#333'
                }
                New-HTMLPanel -Width '25%' -BackgroundColor '#28a745' {
                    New-HTMLText -Text "Low" -FontSize 14 -Color white
                    New-HTMLText -Text $lowCount -FontSize 36 -FontWeight bold -Color white
                }
            }

            # Dashboard Metrics as KPI cards
            if ($Dashboard -and $Dashboard.Count -gt 0) {
                New-HTMLSection -Title 'Server Dashboard' {
                    New-HTMLPanel -Width '33%' -BackgroundColor '#e3f2fd' {
                        New-HTMLText -Text "SQL CPU %" -FontSize 12 -Color '#1565c0'
                        New-HTMLText -Text "$($Dashboard.SQL_CPU_Pct)%" -FontSize 28 -FontWeight bold -Color '#0d47a1'
                    }
                    New-HTMLPanel -Width '33%' -BackgroundColor '#e8f5e9' {
                        New-HTMLText -Text "Signal Wait %" -FontSize 12 -Color '#2e7d32'
                        New-HTMLText -Text "$($Dashboard.Signal_Wait_Pct)%" -FontSize 28 -FontWeight bold -Color '#1b5e20'
                    }
                    New-HTMLPanel -Width '33%' -BackgroundColor '#fff3e0' {
                        New-HTMLText -Text "PLE (seconds)" -FontSize 12 -Color '#e65100'
                        New-HTMLText -Text "$($Dashboard.PLE_Seconds)" -FontSize 28 -FontWeight bold -Color '#bf360c'
                    }
                    New-HTMLPanel -Width '33%' -BackgroundColor '#f3e5f5' {
                        New-HTMLText -Text "Total Memory" -FontSize 12 -Color '#6a1b9a'
                        New-HTMLText -Text "$($Dashboard.Total_Memory_GB) GB" -FontSize 28 -FontWeight bold -Color '#4a148c'
                    }
                    New-HTMLPanel -Width '33%' -BackgroundColor '#e0f7fa' {
                        New-HTMLText -Text "Instance Start" -FontSize 12 -Color '#00838f'
                        New-HTMLText -Text "$($Dashboard.Instance_Start_Time)" -FontSize 14 -FontWeight bold -Color '#006064'
                    }
                    New-HTMLPanel -Width '33%' -BackgroundColor $scoreColor {
                        New-HTMLText -Text "Health Score" -FontSize 12 -Color white
                        New-HTMLText -Text "$HealthScore / 100" -FontSize 28 -FontWeight bold -Color white
                        New-HTMLText -Text $TrafficLight -FontSize 14 -Color white
                    }
                }
            }

            # Findings Table
            if ($Findings -and $Findings.Count -gt 0) {
                New-HTMLSection -Title 'Findings Detail' {
                    $findingsData = $Findings | ForEach-Object {
                        [PSCustomObject]@{
                            CheckId        = $_.CheckId
                            Severity       = $_.Severity
                            Area           = $_.Area
                            Finding        = $_.Finding
                            Impact         = $_.Impact
                            Recommendation = $_.Recommendation
                            NextStep       = $_.NextStepCommand
                        }
                    }
                    New-HTMLTable -DataTable $findingsData -DisablePaging
                }
            }

            # Section Results
            foreach ($section in ($Sections | Where-Object { $_.Rows -and $_.Rows.Count -gt 0 })) {
                New-HTMLSection -Title $section.Section {
                    # Convert DataRows to plain objects
                    $rows = $section.Rows | ForEach-Object {
                        $row = $_
                        $obj = [PSCustomObject]@{}
                        $_.Table.Columns | ForEach-Object {
                            $colName = $_.ColumnName
                            $obj | Add-Member -MemberType NoteProperty -Name $colName -Value $row.$colName
                        }
                        $obj
                    }
                    if ($rows.Count -gt 0) {
                        New-HTMLTable -DataTable $rows -DisablePaging
                    } else {
                        New-HTMLText -Text "No data available." -FontSize 14 -Color '#888'
                    }
                }
            }
        }

        New-HTMLFooter {
            New-HTMLPanel -Width '100%' {
                New-HTMLText -Text 'Generated by SQL Optima DBA Assessment Framework' -FontSize 10 -FontStyle italic -Color '#90a4ae'
            }
        }
    }

    return $fullPath
}