function Invoke-SectionCollector {
    <#
    .SYNOPSIS
        Executes a SQL assessment section and returns structured results.
    .PARAMETER SqlInstance
        SQL Server instance name or SMO server object (from Connect-DbaInstance).
    .PARAMETER DatabaseName
        Database context for execution.
    .PARAMETER Query
        SQL query or stored procedure call to execute.
    .PARAMETER SectionName
        Name of the section for logging.
    .PARAMETER Credential
        PSCredential for SQL authentication.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SqlInstance,
        [string]$DatabaseName = 'DBARepository',
        [Parameter(Mandatory)]
        [string]$Query,
        [string]$SectionName = 'Unknown',
        [PSCredential]$Credential
    )

    $result = [PSCustomObject]@{
        Section      = $SectionName
        CollectedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Rows         = @()
        DataSet      = $null
        Error        = $null
        Duration     = 0
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $params = @{
            SqlInstance = $SqlInstance
            Database    = $DatabaseName
            Query       = $Query
            As          = 'DataSet'
        }
        if ($Credential) { $params.Credential = $Credential }

        $dataSet = Invoke-DbaQuery @params

        $result.DataSet = $dataSet

        if ($dataSet.Tables.Count -gt 0) {
            $result.Rows = $dataSet.Tables[0].Rows
        }
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Warning "Section '$SectionName' failed: $($result.Error)"
    }
    finally {
        $stopwatch.Stop()
        $result.Duration = $stopwatch.Elapsed.TotalSeconds
    }

    return $result
}
