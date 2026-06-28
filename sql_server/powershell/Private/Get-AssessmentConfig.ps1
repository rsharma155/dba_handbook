function Get-AssessmentConfig {
    <#
    .SYNOPSIS
        Loads assessment configuration from JSON file or defaults.
    .PARAMETER ConfigPath
        Path to assessment.config.json. If not provided, uses default location.
    .PARAMETER Profile
        Override the profile in config file (Quick, Standard, Deep).
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [ValidateSet('Quick', 'Standard', 'Deep')]
        [string]$Profile
    )

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'config') 'assessment.config.json'
    }

    $config = if (Test-Path $ConfigPath) {
        Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } else {
        Write-Warning "Config file not found at $ConfigPath. Using defaults."
        [PSCustomObject]@{
            Profile             = 'Quick'
            DatabaseList        = $null
            BackupHoursSLA      = 24
            RegressionPctThreshold = 50
            Sections            = @{
                Inventory   = $true
                HealthCheck = $true
                Waits       = $true
                Backup      = $true
                Security    = $true
                Config      = $true
                DiskLatency = $true
                TempDb      = $true
                QueryStore  = $true
                IndexDeep   = $false
            }
            PersistToRepository = $false
            OutputFormat        = 'HTML'
            IncludeDeepDive     = $false
        }
    }

    if ($Profile) {
        $config.Profile = $Profile
    }

    # Apply profile presets
    switch ($config.Profile) {
        'Quick' {
            $config.IncludeDeepDive = $false
            $config.Sections.IndexDeep = $false
        }
        'Standard' {
            $config.IncludeDeepDive = $false
            $config.Sections.IndexDeep = $false
        }
        'Deep' {
            $config.IncludeDeepDive = $true
            $config.Sections.IndexDeep = $true
        }
    }

    return $config
}
