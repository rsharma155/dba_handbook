#Requires -Version 5.1
<#
.SYNOPSIS
  Windows Forms GUI for SQL Schema Compare & Sync.

.DESCRIPTION
  Thin UI wrapper around the existing schema_compare scripts. Does NOT modify
  schema_compare\Compare-SqlSchema.ps1 or related files - it only calls them.

  Launch (STA required for WinForms):
    .\Launch-SchemaCompareGui.cmd
    or
    powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\Start-SchemaCompareGui.ps1

.NOTES
  Requires: PowerShell 5.1+, Windows, dbatools (same as schema_compare).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# WinForms must run in STA
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$PSCommandPath`"")
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argList -Wait
    exit $LASTEXITCODE
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot 'SchemaCompareGui.Helpers.ps1')

$script:GuiRoot       = $PSScriptRoot
$script:CompareRoot   = Get-SchemaCompareRoot -GuiRoot $script:GuiRoot
$script:CompareScript = Join-Path $script:CompareRoot 'Compare-SqlSchema.ps1'
$script:TestScript    = Join-Path $script:CompareRoot 'Test-SqlSchemaConnection.ps1'
$script:SettingsPath  = Get-GuiSettingsPath -GuiRoot $script:GuiRoot
$script:DefaultOutput = Join-Path $script:CompareRoot 'output'
$script:IsBusy             = $false
$script:LastReport         = $null
$script:LastScriptDir      = $null
$script:Runspace           = $null
$script:AsyncResult        = $null
$script:PsInstance         = $null
$script:SyncHash           = $null
$script:LogCursor          = 0
$script:PreferredSourceDb  = $null
$script:PreferredTargetDbs = @()

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 90, [int]$H = 20)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.Location = [Drawing.Point]::new($X, $Y); $l.Size = [Drawing.Size]::new($W, $H)
    $l.AutoSize = $false
    return $l
}
function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 180, [int]$H = 22, [string]$Text = '')
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = [Drawing.Point]::new($X, $Y); $t.Size = [Drawing.Size]::new($W, $H); $t.Text = $Text
    return $t
}
function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 100, [int]$H = 26)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Location = [Drawing.Point]::new($X, $Y); $b.Size = [Drawing.Size]::new($W, $H)
    $b.FlatStyle = 'System'
    return $b
}
function Append-Log {
    param([string]$Message, [string]$ColorName = 'Black')
    if (-not $txtLog -or $txtLog.IsDisposed) { return }
    $ts = (Get-Date).ToString('HH:mm:ss')
    $line = "[$ts] $Message"
    if ($txtLog.InvokeRequired) {
        $txtLog.BeginInvoke([Action[string]]{ param($m) $txtLog.AppendText("$m`r`n") }, $line) | Out-Null
    } else {
        $txtLog.AppendText("$line`r`n")
    }
}
function Set-Status {
    param([string]$Text)
    if ($statusLabel.InvokeRequired) {
        $statusLabel.BeginInvoke([Action[string]]{ param($t) $statusLabel.Text = $t }, $Text) | Out-Null
    } else {
        $statusLabel.Text = $Text
    }
}
function Set-BusyUi {
    param([bool]$Busy)
    $script:IsBusy = $Busy
    $btnRun.Enabled = -not $Busy
    $btnTestSrc.Enabled = -not $Busy
    $btnTestTgt.Enabled = -not $Busy
    $btnRefreshSrc.Enabled = -not $Busy
    $btnRefreshTgt.Enabled = -not $Busy
    $progress.Style = if ($Busy) { 'Marquee' } else { 'Blocks' }
    $progress.MarqueeAnimationSpeed = if ($Busy) { 30 } else { 0 }
}

function Get-PortValue {
    param([System.Windows.Forms.TextBox]$Box)
    $t = $Box.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return 0 }
    $n = 0
    if (-not [int]::TryParse($t, [ref]$n)) { throw "Port must be a number: '$t'" }
    return $n
}

function Get-SideCredential {
    param(
        [System.Windows.Forms.RadioButton]$SqlAuth,
        [System.Windows.Forms.TextBox]$User,
        [System.Windows.Forms.TextBox]$Pass
    )
    if (-not $SqlAuth.Checked) { return $null }
    if ([string]::IsNullOrWhiteSpace($User.Text)) {
        throw 'SQL authentication selected but username is empty.'
    }
    return (New-SqlCredentialFromPlain -UserName $User.Text.Trim() -Password $Pass.Text)
}

function Update-ModeUi {
    $oneToMany = $rbOneToMany.Checked
    $lblTargetDb.Text = if ($oneToMany) { 'Target DBs (multi):' } else { 'Target DB:' }
    $clbTargetDbs.Enabled = $true
    $btnLoadList.Enabled = $oneToMany
    $txtListFile.Enabled = $oneToMany
    $btnBrowseList.Enabled = $oneToMany
    if (-not $oneToMany) {
        # Single-select feel: leave checklist but hint in status
        Set-Status 'Mode: One-to-One - select matching source/target databases (or same name).'
    } else {
        Set-Status 'Mode: One-to-Many - one source DB, check multiple target DBs or load a list file.'
    }
}

function Get-CheckedTargetDatabases {
    $checked = New-Object System.Collections.Generic.List[string]
    if ($clbTargetDbs.Items.Count -eq 0) { return @() }
    for ($i = 0; $i -lt $clbTargetDbs.Items.Count; $i++) {
        if ($clbTargetDbs.GetItemChecked($i)) { $checked.Add([string]$clbTargetDbs.Items[$i]) }
    }
    return @($checked)
}

function Save-CurrentSettings {
    $checked = @(Get-CheckedTargetDatabases)
    $settings = @{
        Mode                   = if ($rbOneToMany.Checked) { 'OneToMany' } else { 'OneToOne' }
        SourceSqlInstance      = $txtSrcInst.Text.Trim()
        TargetSqlInstance      = $txtTgtInst.Text.Trim()
        SourcePort             = $txtSrcPort.Text.Trim()
        TargetPort             = $txtTgtPort.Text.Trim()
        NetworkProtocol        = [string]$cmbProtocol.SelectedItem
        SourceSqlAuth          = [bool]$rbSrcSql.Checked
        TargetSqlAuth          = [bool]$rbTgtSql.Checked
        SourceUser             = $txtSrcUser.Text.Trim()
        TargetUser             = $txtTgtUser.Text.Trim()
        SourceDatabase         = [string]$cmbSourceDb.Text
        TargetDatabases        = $checked
        TargetDatabaseListFile = $txtListFile.Text.Trim()
        GenerateSyncScript     = [bool]$chkGenerate.Checked
        IncludeDrops           = [bool]$chkDrops.Checked
        Apply                  = [bool]$chkApply.Checked
        TrustServerCertificate = [bool]$chkTrust.Checked
        ExcludeSchema          = $txtExclude.Text.Trim()
        OutputPath             = $txtOutput.Text.Trim()
        ConnectionTimeout      = $txtTimeout.Text.Trim()
    }
    # Never persist passwords
    Save-GuiSettings -Settings $settings -Path $script:SettingsPath
}

function Load-SavedSettings {
    $s = Read-GuiSettings -Path $script:SettingsPath
    if (-not $s) { return }
    try {
        if ($s.Mode -eq 'OneToMany') { $rbOneToMany.Checked = $true } else { $rbOneToOne.Checked = $true }
        if ($s.SourceSqlInstance) { $txtSrcInst.Text = $s.SourceSqlInstance }
        if ($s.TargetSqlInstance) { $txtTgtInst.Text = $s.TargetSqlInstance }
        if ($s.PSObject.Properties['SourcePort']) { $txtSrcPort.Text = [string]$s.SourcePort }
        if ($s.PSObject.Properties['TargetPort']) { $txtTgtPort.Text = [string]$s.TargetPort }
        if ($s.NetworkProtocol -and $cmbProtocol.Items.Contains($s.NetworkProtocol)) {
            $cmbProtocol.SelectedItem = $s.NetworkProtocol
        }
        if ($s.SourceSqlAuth) { $rbSrcSql.Checked = $true } else { $rbSrcWin.Checked = $true }
        if ($s.TargetSqlAuth) { $rbTgtSql.Checked = $true } else { $rbTgtWin.Checked = $true }
        if ($s.SourceUser) { $txtSrcUser.Text = $s.SourceUser }
        if ($s.TargetUser) { $txtTgtUser.Text = $s.TargetUser }
        if ($s.TargetDatabaseListFile) { $txtListFile.Text = $s.TargetDatabaseListFile }
        if ($s.PSObject.Properties['GenerateSyncScript']) { $chkGenerate.Checked = [bool]$s.GenerateSyncScript }
        if ($s.PSObject.Properties['IncludeDrops']) { $chkDrops.Checked = [bool]$s.IncludeDrops }
        if ($s.PSObject.Properties['Apply']) { $chkApply.Checked = [bool]$s.Apply }
        if ($s.PSObject.Properties['TrustServerCertificate']) { $chkTrust.Checked = [bool]$s.TrustServerCertificate }
        if ($s.ExcludeSchema) { $txtExclude.Text = $s.ExcludeSchema }
        if ($s.OutputPath) { $txtOutput.Text = $s.OutputPath }
        if ($s.ConnectionTimeout) { $txtTimeout.Text = [string]$s.ConnectionTimeout }
        # DBs loaded after refresh; stash preferred names
        $script:PreferredSourceDb = [string]$s.SourceDatabase
        $script:PreferredTargetDbs = @($s.TargetDatabases)
    } catch {
        Append-Log "Could not restore all settings: $($_.Exception.Message)" 'DarkOrange'
    }
}

# ---------------------------------------------------------------------------
# Main form
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SQL Schema Compare & Sync'
$form.Size = [Drawing.Size]::new(980, 780)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = [Drawing.Size]::new(900, 700)
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

# --- Header ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = 'Top'
$pnlHeader.Height = 52
$pnlHeader.BackColor = [Drawing.Color]::FromArgb(24, 55, 85)
$form.Controls.Add($pnlHeader)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'SQL Schema Compare & Sync'
$lblTitle.ForeColor = [Drawing.Color]::White
$lblTitle.Font = New-Object Drawing.Font('Segoe UI Semibold', 14)
$lblTitle.Location = [Drawing.Point]::new(16, 12)
$lblTitle.AutoSize = $true
$pnlHeader.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "GUI wrapper - calls existing schema_compare scripts (read-only integration)"
$lblSub.ForeColor = [Drawing.Color]::FromArgb(180, 210, 235)
$lblSub.Location = [Drawing.Point]::new(320, 18)
$lblSub.AutoSize = $true
$pnlHeader.Controls.Add($lblSub)

# --- Mode ---
$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = 'Compare mode'
$grpMode.Location = [Drawing.Point]::new(12, 60)
$grpMode.Size = [Drawing.Size]::new(940, 48)
$form.Controls.Add($grpMode)

$rbOneToOne = New-Object System.Windows.Forms.RadioButton
$rbOneToOne.Text = 'One-to-One  (source DB -> matching target DB)'
$rbOneToOne.Location = [Drawing.Point]::new(16, 18)
$rbOneToOne.AutoSize = $true
$rbOneToOne.Checked = $true
$grpMode.Controls.Add($rbOneToOne)

$rbOneToMany = New-Object System.Windows.Forms.RadioButton
$rbOneToMany.Text = 'One-to-Many  (one source DB -> many target DBs on one server)'
$rbOneToMany.Location = [Drawing.Point]::new(420, 18)
$rbOneToMany.AutoSize = $true
$grpMode.Controls.Add($rbOneToMany)

# --- Source panel ---
$grpSrc = New-Object System.Windows.Forms.GroupBox
$grpSrc.Text = 'Source (source of truth)'
$grpSrc.Location = [Drawing.Point]::new(12, 116)
$grpSrc.Size = [Drawing.Size]::new(460, 250)
$form.Controls.Add($grpSrc)

$grpSrc.Controls.Add((New-Label 'Instance:' 12 28 70))
$txtSrcInst = New-TextBox 90 26 220 22 '.'
$grpSrc.Controls.Add($txtSrcInst)
$grpSrc.Controls.Add((New-Label 'Port:' 320 28 36))
$txtSrcPort = New-TextBox 360 26 70 22 ''
$grpSrc.Controls.Add($txtSrcPort)

$rbSrcWin = New-Object System.Windows.Forms.RadioButton
$rbSrcWin.Text = 'Windows auth'; $rbSrcWin.Location = [Drawing.Point]::new(12, 58); $rbSrcWin.AutoSize = $true; $rbSrcWin.Checked = $true
$rbSrcSql = New-Object System.Windows.Forms.RadioButton
$rbSrcSql.Text = 'SQL auth'; $rbSrcSql.Location = [Drawing.Point]::new(140, 58); $rbSrcSql.AutoSize = $true
$grpSrc.Controls.Add($rbSrcWin); $grpSrc.Controls.Add($rbSrcSql)

$grpSrc.Controls.Add((New-Label 'Login:' 12 88 70))
$txtSrcUser = New-TextBox 90 86 140
$grpSrc.Controls.Add($txtSrcUser)
$grpSrc.Controls.Add((New-Label 'Password:' 240 88 60))
$txtSrcPass = New-TextBox 305 86 125
$txtSrcPass.UseSystemPasswordChar = $true
$grpSrc.Controls.Add($txtSrcPass)

$btnTestSrc = New-Button 'Test connection' 12 120 120
$btnRefreshSrc = New-Button 'Refresh databases' 140 120 130
$grpSrc.Controls.Add($btnTestSrc); $grpSrc.Controls.Add($btnRefreshSrc)

$grpSrc.Controls.Add((New-Label 'Source DB:' 12 160 80))
$cmbSourceDb = New-Object System.Windows.Forms.ComboBox
$cmbSourceDb.Location = [Drawing.Point]::new(90, 158)
$cmbSourceDb.Size = [Drawing.Size]::new(340, 24)
$cmbSourceDb.DropDownStyle = 'DropDown'  # allow typing if refresh unavailable
$grpSrc.Controls.Add($cmbSourceDb)

$lblSrcHint = New-Label 'Tip: Refresh loads user databases from the instance via dbatools.' 12 195 430 36
$lblSrcHint.ForeColor = [Drawing.Color]::DimGray
$grpSrc.Controls.Add($lblSrcHint)

# --- Target panel ---
$grpTgt = New-Object System.Windows.Forms.GroupBox
$grpTgt.Text = 'Target (will be synced toward source)'
$grpTgt.Location = [Drawing.Point]::new(492, 116)
$grpTgt.Size = [Drawing.Size]::new(460, 250)
$form.Controls.Add($grpTgt)

$grpTgt.Controls.Add((New-Label 'Instance:' 12 28 70))
$txtTgtInst = New-TextBox 90 26 220 22 ''
$grpTgt.Controls.Add($txtTgtInst)
$grpTgt.Controls.Add((New-Label 'Port:' 320 28 36))
$txtTgtPort = New-TextBox 360 26 70 22 ''
$grpTgt.Controls.Add($txtTgtPort)

$rbTgtWin = New-Object System.Windows.Forms.RadioButton
$rbTgtWin.Text = 'Windows auth'; $rbTgtWin.Location = [Drawing.Point]::new(12, 58); $rbTgtWin.AutoSize = $true; $rbTgtWin.Checked = $true
$rbTgtSql = New-Object System.Windows.Forms.RadioButton
$rbTgtSql.Text = 'SQL auth'; $rbTgtSql.Location = [Drawing.Point]::new(140, 58); $rbTgtSql.AutoSize = $true
$grpTgt.Controls.Add($rbTgtWin); $grpTgt.Controls.Add($rbTgtSql)

$grpTgt.Controls.Add((New-Label 'Login:' 12 88 70))
$txtTgtUser = New-TextBox 90 86 140
$grpTgt.Controls.Add($txtTgtUser)
$grpTgt.Controls.Add((New-Label 'Password:' 240 88 60))
$txtTgtPass = New-TextBox 305 86 125
$txtTgtPass.UseSystemPasswordChar = $true
$grpTgt.Controls.Add($txtTgtPass)

$btnTestTgt = New-Button 'Test connection' 12 120 120
$btnRefreshTgt = New-Button 'Refresh databases' 140 120 130
$grpTgt.Controls.Add($btnTestTgt); $grpTgt.Controls.Add($btnRefreshTgt)

$lblTargetDb = New-Label 'Target DB:' 12 156 120
$grpTgt.Controls.Add($lblTargetDb)
$clbTargetDbs = New-Object System.Windows.Forms.CheckedListBox
$clbTargetDbs.Location = [Drawing.Point]::new(12, 178)
$clbTargetDbs.Size = [Drawing.Size]::new(430, 60)
$clbTargetDbs.CheckOnClick = $true
$grpTgt.Controls.Add($clbTargetDbs)

# --- Shared connection / options ---
$grpOpts = New-Object System.Windows.Forms.GroupBox
$grpOpts.Text = 'Options'
$grpOpts.Location = [Drawing.Point]::new(12, 374)
$grpOpts.Size = [Drawing.Size]::new(940, 130)
$form.Controls.Add($grpOpts)

$grpOpts.Controls.Add((New-Label 'Protocol:' 12 28 70))
$cmbProtocol = New-Object System.Windows.Forms.ComboBox
$cmbProtocol.DropDownStyle = 'DropDownList'
$cmbProtocol.Location = [Drawing.Point]::new(85, 26)
$cmbProtocol.Size = [Drawing.Size]::new(140, 24)
@('TcpIp','NamedPipes','SharedMemory') | ForEach-Object { [void]$cmbProtocol.Items.Add($_) }
$cmbProtocol.SelectedItem = 'TcpIp'
$grpOpts.Controls.Add($cmbProtocol)

$grpOpts.Controls.Add((New-Label 'Timeout (s):' 240 28 80))
$txtTimeout = New-TextBox 325 26 50 22 '30'
$grpOpts.Controls.Add($txtTimeout)

$chkTrust = New-Object System.Windows.Forms.CheckBox
$chkTrust.Text = 'Trust server certificate'
$chkTrust.Location = [Drawing.Point]::new(400, 26)
$chkTrust.AutoSize = $true
$chkTrust.Checked = $true
$grpOpts.Controls.Add($chkTrust)

$chkGenerate = New-Object System.Windows.Forms.CheckBox
$chkGenerate.Text = 'Generate sync scripts'
$chkGenerate.Location = [Drawing.Point]::new(12, 58)
$chkGenerate.AutoSize = $true
$chkGenerate.Checked = $true
$grpOpts.Controls.Add($chkGenerate)

$chkDrops = New-Object System.Windows.Forms.CheckBox
$chkDrops.Text = 'Include drops (destructive)'
$chkDrops.Location = [Drawing.Point]::new(180, 58)
$chkDrops.AutoSize = $true
$grpOpts.Controls.Add($chkDrops)

$chkApply = New-Object System.Windows.Forms.CheckBox
$chkApply.Text = 'Apply auto_ scripts on target'
$chkApply.Location = [Drawing.Point]::new(390, 58)
$chkApply.AutoSize = $true
$chkApply.ForeColor = [Drawing.Color]::DarkRed
$grpOpts.Controls.Add($chkApply)

$grpOpts.Controls.Add((New-Label 'Exclude schemas:' 12 90 110))
$txtExclude = New-TextBox 125 88 300 22 'sys,INFORMATION_SCHEMA,guest'
$grpOpts.Controls.Add($txtExclude)

$grpOpts.Controls.Add((New-Label 'Output folder:' 440 90 90))
$txtOutput = New-TextBox 535 88 280 22 $script:DefaultOutput
$grpOpts.Controls.Add($txtOutput)
$btnBrowseOut = New-Button '...' 825 86 40
$grpOpts.Controls.Add($btnBrowseOut)

# List file row (one-to-many)
$grpList = New-Object System.Windows.Forms.GroupBox
$grpList.Text = 'Destination list file (optional - one-to-many)'
$grpList.Location = [Drawing.Point]::new(12, 510)
$grpList.Size = [Drawing.Size]::new(940, 58)
$form.Controls.Add($grpList)

$txtListFile = New-TextBox 12 24 700
$grpList.Controls.Add($txtListFile)
$btnBrowseList = New-Button 'Browse...' 720 22 90
$btnLoadList = New-Button 'Load into list' 820 22 100
$grpList.Controls.Add($btnBrowseList); $grpList.Controls.Add($btnLoadList)

# --- Actions ---
$btnRun = New-Button 'Run compare' 12 578 130 32
$btnRun.Font = New-Object Drawing.Font('Segoe UI Semibold', 10)
$btnOpenOut = New-Button 'Open output folder' 152 578 140 32
$btnOpenReport = New-Button 'Open HTML report' 302 578 140 32
$btnSaveSettings = New-Button 'Save settings' 452 578 110 32
$btnClearLog = New-Button 'Clear log' 572 578 90 32
$form.Controls.AddRange(@($btnRun, $btnOpenOut, $btnOpenReport, $btnSaveSettings, $btnClearLog))

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = [Drawing.Point]::new(680, 582)
$progress.Size = [Drawing.Size]::new(270, 24)
$form.Controls.Add($progress)

# --- Log ---
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Both'
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object Drawing.Font('Consolas', 9)
$txtLog.Location = [Drawing.Point]::new(12, 618)
$txtLog.Size = [Drawing.Size]::new(940, 90)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($txtLog)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
[void]$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = 400

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
$rbOneToOne.Add_CheckedChanged({ if ($rbOneToOne.Checked) { Update-ModeUi } })
$rbOneToMany.Add_CheckedChanged({ if ($rbOneToMany.Checked) { Update-ModeUi } })

$btnClearLog.Add_Click({ $txtLog.Clear() })
$btnSaveSettings.Add_Click({
    try {
        Save-CurrentSettings
        Append-Log "Settings saved to $($script:SettingsPath)"
        Set-Status 'Settings saved (passwords not stored).'
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Save settings', 'OK', 'Error') | Out-Null
    }
})

$btnBrowseOut.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select output folder for sync scripts and HTML report'
    if (Test-Path $txtOutput.Text) { $dlg.SelectedPath = $txtOutput.Text }
    if ($dlg.ShowDialog() -eq 'OK') { $txtOutput.Text = $dlg.SelectedPath }
})

$btnBrowseList.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'List files (*.json;*.yml;*.yaml;*.txt)|*.json;*.yml;*.yaml;*.txt|All files (*.*)|*.*'
    $dlg.Title = 'Select destination database list file'
    $defaultList = Join-Path $script:CompareRoot 'config\destination_databases.json'
    if (Test-Path $defaultList) { $dlg.InitialDirectory = (Split-Path $defaultList) }
    if ($dlg.ShowDialog() -eq 'OK') { $txtListFile.Text = $dlg.FileName }
})

$btnLoadList.Add_Click({
    try {
        $path = $txtListFile.Text.Trim()
        if (-not $path) { throw 'Choose a list file first.' }
        # Reuse parser from Compare-SqlSchema by dot-sourcing only the function is hard;
        # call a tiny inline load using the same formats via helpers in Compare... 
        # Simplest: invoke Resolve by temporarily loading function from Compare file is heavy.
        # Parse here for UI population only - Compare script still owns authoritative parsing at run.
        if (-not (Test-Path -LiteralPath $path)) { throw "File not found: $path" }
        $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
        $names = New-Object System.Collections.Generic.List[string]
        $raw = Get-Content -LiteralPath $path -Raw
        switch ($ext) {
            '.txt' {
                foreach ($line in ($raw -split '\r?\n')) {
                    $t = $line.Trim()
                    if (-not $t -or $t.StartsWith('#')) { continue }
                    $names.Add($t)
                }
            }
            '.json' {
                $obj = $raw | ConvertFrom-Json
                $list = if ($obj -is [string]) { @($obj) }
                    elseif ($obj -is [System.Array]) { @($obj) }
                    elseif ($obj.PSObject.Properties['DestinationDatabases']) { @($obj.DestinationDatabases) }
                    elseif ($obj.PSObject.Properties['TargetDatabases']) { @($obj.TargetDatabases) }
                    elseif ($obj.PSObject.Properties['Databases']) { @($obj.Databases) }
                    else { throw 'Unrecognized JSON list format.' }
                foreach ($n in $list) { if ($n) { $names.Add([string]$n) } }
            }
            { $_ -in '.yml', '.yaml' } {
                $inList = $false
                foreach ($line in ($raw -split '\r?\n')) {
                    $stripped = ($line -replace '#.*$', '').TrimEnd()
                    if ($stripped -match '^(DestinationDatabases|TargetDatabases|Databases)\s*:') { $inList = $true; continue }
                    if ($stripped -match '^\-\s+(.+)$' -and $inList) { $names.Add($Matches[1].Trim().Trim('''"')) }
                }
            }
            default { throw "Unsupported extension: $ext" }
        }
        if ($names.Count -eq 0) { throw 'No database names found in file.' }
        $clbTargetDbs.Items.Clear()
        foreach ($n in $names) {
            [void]$clbTargetDbs.Items.Add($n, $true)
        }
        $rbOneToMany.Checked = $true
        Append-Log "Loaded $($names.Count) destination database(s) from list file."
        Set-Status "Loaded $($names.Count) targets from list file."
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Load list file', 'OK', 'Error') | Out-Null
    }
})

$btnOpenOut.Add_Click({
    $dir = if ($script:LastScriptDir -and (Test-Path $script:LastScriptDir)) {
        $script:LastScriptDir
    } elseif (Test-Path $txtOutput.Text) {
        $txtOutput.Text
    } else { $null }
    if (-not $dir) {
        [System.Windows.Forms.MessageBox]::Show('No output folder yet. Run a compare with Generate sync scripts enabled.', 'Open output') | Out-Null
        return
    }
    Start-Process explorer.exe $dir
})

$btnOpenReport.Add_Click({
    if ($script:LastReport -and (Test-Path $script:LastReport)) {
        Start-Process $script:LastReport
    } else {
        [System.Windows.Forms.MessageBox]::Show('No HTML report from this session yet.', 'Open report') | Out-Null
    }
})

function Test-SideConnection {
    param([string]$Role)
    try {
        Set-BusyUi $true
        Set-Status "Testing $Role connection..."
        if ($Role -eq 'Source') {
            $inst = $txtSrcInst.Text.Trim()
            $port = Get-PortValue $txtSrcPort
            $cred = Get-SideCredential $rbSrcSql $txtSrcUser $txtSrcPass
        } else {
            $inst = $txtTgtInst.Text.Trim()
            $port = Get-PortValue $txtTgtPort
            $cred = Get-SideCredential $rbTgtSql $txtTgtUser $txtTgtPass
        }
        if (-not $inst) { throw "$Role instance is required." }

        $args = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($script:TestScript)`"",
            '-SqlInstance', $inst,
            '-NetworkProtocol', ([string]$cmbProtocol.SelectedItem),
            '-Database', 'master'
        )
        if ($port -gt 0) { $args += @('-Port', "$port") }
        if ($chkTrust.Checked) { $args += '-TrustServerCertificate' }

        # For SQL auth, write a tiny wrapper so password is not on the process command line length forever -
        # still visible in process list briefly; acceptable for admin tool on workstation.
        $tmp = $null
        if ($cred) {
            $tmp = Join-Path $env:TEMP ("SchemaCompareGui_Test_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
            $userEsc = $cred.UserName.Replace("'", "''")
            $passPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password))
            $passEsc = $passPlain.Replace("'", "''")
            @"
`$sec = ConvertTo-SecureString '$passEsc' -AsPlainText -Force
`$cred = New-Object pscredential('$userEsc', `$sec)
& '$($script:TestScript)' -SqlInstance '$inst' -NetworkProtocol '$([string]$cmbProtocol.SelectedItem)' -Database master -Credential `$cred $(if($port -gt 0){"-Port $port"}) $(if($chkTrust.Checked){'-TrustServerCertificate'})
"@ | Set-Content -Path $tmp -Encoding UTF8
            $psiArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tmp`"")
        } else {
            $psiArgs = $args
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = ($psiArgs -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        Append-Log "--- $Role connection test ---"
        if ($out) { $out -split "`r?`n" | ForEach-Object { if ($_) { Append-Log $_ } } }
        if ($err) { $err -split "`r?`n" | ForEach-Object { if ($_) { Append-Log "ERR: $_" } } }
        if ($p.ExitCode -eq 0) {
            Set-Status "$Role connection test finished (exit 0). Review log."
        } else {
            Set-Status "$Role connection test finished with exit $($p.ExitCode)."
        }
    } catch {
        Append-Log "Test failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Test $Role", 'OK', 'Error') | Out-Null
    } finally {
        Set-BusyUi $false
    }
}

$btnTestSrc.Add_Click({ Test-SideConnection 'Source' })
$btnTestTgt.Add_Click({ Test-SideConnection 'Target' })

function Refresh-Databases {
    param([ValidateSet('Source','Target')][string]$Role)
    try {
        Set-BusyUi $true
        Set-Status "Refreshing $Role databases..."
        if ($Role -eq 'Source') {
            $inst = $txtSrcInst.Text.Trim()
            $port = Get-PortValue $txtSrcPort
            $cred = Get-SideCredential $rbSrcSql $txtSrcUser $txtSrcPass
        } else {
            $inst = $txtTgtInst.Text.Trim()
            $port = Get-PortValue $txtTgtPort
            $cred = Get-SideCredential $rbTgtSql $txtTgtUser $txtTgtPass
        }
        if (-not $inst) { throw "$Role instance is required." }

        $dbs = Get-UserDatabasesOnInstance -SqlInstance $inst -Port $port `
            -NetworkProtocol ([string]$cmbProtocol.SelectedItem) `
            -Credential $cred -TrustServerCertificate:$chkTrust.Checked

        if ($Role -eq 'Source') {
            $cmbSourceDb.Items.Clear()
            foreach ($d in $dbs) { [void]$cmbSourceDb.Items.Add($d) }
            if ($script:PreferredSourceDb -and $cmbSourceDb.Items.Contains($script:PreferredSourceDb)) {
                $cmbSourceDb.SelectedItem = $script:PreferredSourceDb
            } elseif ($cmbSourceDb.Items.Count -gt 0) {
                $cmbSourceDb.SelectedIndex = 0
            }
        } else {
            $prevChecked = @{}
            if ($clbTargetDbs.Items.Count -gt 0) {
                for ($i = 0; $i -lt $clbTargetDbs.Items.Count; $i++) {
                    if ($clbTargetDbs.GetItemChecked($i)) { $prevChecked[[string]$clbTargetDbs.Items[$i]] = $true }
                }
            }
            $clbTargetDbs.Items.Clear()
            $preferred = @($script:PreferredTargetDbs)
            foreach ($d in $dbs) {
                $check = $prevChecked.ContainsKey($d) -or ($preferred -contains $d)
                [void]$clbTargetDbs.Items.Add($d, [bool]$check)
            }
        }
        Append-Log "${Role}: loaded $($dbs.Count) user database(s)."
        Set-Status "$Role databases refreshed ($($dbs.Count))."
    } catch {
        Append-Log "Refresh $Role failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "$($_.Exception.Message)`r`n`r`nYou can still type database names manually.",
            "Refresh $Role databases", 'OK', 'Warning') | Out-Null
    } finally {
        Set-BusyUi $false
    }
}

$btnRefreshSrc.Add_Click({ Refresh-Databases 'Source' })
$btnRefreshTgt.Add_Click({ Refresh-Databases 'Target' })

function Complete-Run {
    param($SyncHash)
    try {
        $pollTimer.Stop()
        if ($SyncHash.Log) {
            foreach ($line in @($SyncHash.Log)) { Append-Log $line }
        }
        if ($SyncHash.Error) {
            Append-Log "ERROR: $($SyncHash.Error)"
            Set-Status 'Compare failed.'
            [System.Windows.Forms.MessageBox]::Show($SyncHash.Error, 'Schema compare failed', 'OK', 'Error') | Out-Null
            return
        }
        $results = @($SyncHash.Results)
        if ($results.Count -eq 0) {
            Append-Log 'Compare finished (no summary objects returned).'
        } else {
            Append-Log '--- Summary ---'
            foreach ($r in $results) {
                $line = "Source=$($r.Database) Target=$($r.TargetDatabase) Diffs=$($r.DifferenceCount) Auto=$($r.AutoScripts) Manual=$($r.ManualScripts)"
                Append-Log $line
                if ($r.ScriptFolder) { $script:LastScriptDir = $r.ScriptFolder }
                if ($r.ReportPath) { $script:LastReport = $r.ReportPath }
            }
            # Prefer run root for multi-DB
            if ($script:LastScriptDir) {
                $parent = Split-Path -Parent $script:LastScriptDir
                if ((Split-Path -Leaf $parent) -like 'SchemaSync_*') {
                    $script:LastScriptDir = $parent
                }
            }
        }
        if ($script:LastReport) { Append-Log "HTML report: $($script:LastReport)" }
        if ($script:LastScriptDir) { Append-Log "Scripts: $($script:LastScriptDir)" }
        Set-Status 'Compare completed successfully.'
        try { Save-CurrentSettings } catch { }
        [System.Windows.Forms.MessageBox]::Show(
            "Compare completed.`r`nDifferences summarized in the log.`r`nUse Open output folder / Open HTML report.",
            'Done', 'OK', 'Information') | Out-Null
    } finally {
        if ($script:PsInstance) { $script:PsInstance.Dispose(); $script:PsInstance = $null }
        if ($script:Runspace) { $script:Runspace.Close(); $script:Runspace.Dispose(); $script:Runspace = $null }
        Set-BusyUi $false
    }
}

$pollTimer.Add_Tick({
    if (-not $script:AsyncResult) { return }
    $syncHash = $script:SyncHash
    # Drain new log lines
    while ($syncHash.Log.Count -gt $script:LogCursor) {
        Append-Log ([string]$syncHash.Log[$script:LogCursor])
        $script:LogCursor++
    }
    if ($script:AsyncResult.IsCompleted) {
        Complete-Run -SyncHash $syncHash
        $script:AsyncResult = $null
    }
})

$btnRun.Add_Click({
    if ($script:IsBusy) { return }
    try {
        $srcInst = $txtSrcInst.Text.Trim()
        $tgtInst = $txtTgtInst.Text.Trim()
        if (-not $srcInst) { throw 'Source instance is required.' }
        if (-not $tgtInst) { throw 'Target instance is required.' }

        $srcDb = $cmbSourceDb.Text.Trim()
        if (-not $srcDb) { throw 'Select or type a source database.' }

        $listFile = $txtListFile.Text.Trim()
        $checkedTargets = New-Object System.Collections.Generic.List[string]
        foreach ($n in @(Get-CheckedTargetDatabases)) { $checkedTargets.Add($n) }
        # Allow typing a single target when list is empty: use combo-like - if no checks, and one-to-one with typed items
        if ($clbTargetDbs.Items.Count -eq 0 -and -not $listFile) {
            # Manual entry fallback via Input - use source name for 1:1
            if ($rbOneToOne.Checked) {
                $checkedTargets.Add($srcDb)
            } else {
                throw 'Refresh target databases and check one or more, or load a destination list file.'
            }
        }

        if ($rbOneToMany.Checked) {
            if (-not $listFile -and $checkedTargets.Count -lt 1) {
                throw 'One-to-Many requires checked target databases and/or a list file.'
            }
            if ($listFile -and $checkedTargets.Count -gt 0) {
                # Prefer explicit checklist selections if user checked items; otherwise list file at run time
                # If both set, use checklist (clearer for GUI) unless user only loaded file path for Compare to parse
            }
        } else {
            # One-to-One: exactly one target preferred
            if ($checkedTargets.Count -eq 0) { $checkedTargets.Add($srcDb) }
            if ($checkedTargets.Count -gt 1) {
                $resp = [System.Windows.Forms.MessageBox]::Show(
                    "One-to-One mode has $($checkedTargets.Count) targets checked.`r`nContinue as One-to-Many fan-out instead?",
                    'Multiple targets', 'YesNo', 'Question')
                if ($resp -ne 'Yes') { return }
                $rbOneToMany.Checked = $true
            }
        }

        if ($chkApply.Checked) {
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                "APPLY is enabled.`r`n`r`nThis will execute auto_ scripts on the TARGET server.`r`nmanual_ scripts are never auto-applied.`r`n`r`nContinue?",
                'Confirm Apply', 'YesNo', 'Warning')
            if ($confirm -ne 'Yes') { return }
        }

        $srcCred = Get-SideCredential $rbSrcSql $txtSrcUser $txtSrcPass
        $tgtCred = Get-SideCredential $rbTgtSql $txtTgtUser $txtTgtPass
        $srcPort = Get-PortValue $txtSrcPort
        $tgtPort = Get-PortValue $txtTgtPort
        $timeout = 30
        [void][int]::TryParse($txtTimeout.Text.Trim(), [ref]$timeout)

        $exclude = @($txtExclude.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        $useListFile = ($rbOneToMany.Checked -and $listFile -and $checkedTargets.Count -eq 0)
        $targetDbs = if ($useListFile) { $null } else { @($checkedTargets) }
        $listPath = if ($useListFile) { $listFile } elseif ($rbOneToMany.Checked -and $listFile -and $checkedTargets.Count -eq 0) { $listFile } else { $null }

        # If one-to-many with checks, pass -TargetDatabase array (no list file needed)
        if ($rbOneToMany.Checked -and $checkedTargets.Count -ge 1) {
            $targetDbs = @($checkedTargets)
            $listPath = $null
        } elseif ($rbOneToMany.Checked -and $listFile) {
            $listPath = $listFile
            $targetDbs = $null
        } elseif ($rbOneToOne.Checked) {
            $targetDbs = @($checkedTargets[0])
            $listPath = $null
            # Same name optimization: omit TargetDatabase if identical
            if ($targetDbs[0] -eq $srcDb) { $targetDbs = $null }
        }

        $splat = Build-CompareSplatFromGui `
            -SourceSqlInstance $srcInst `
            -TargetSqlInstance $tgtInst `
            -Database @($srcDb) `
            -TargetDatabase $targetDbs `
            -TargetDatabaseListFile $listPath `
            -SourceCredential $srcCred `
            -TargetCredential $tgtCred `
            -SourcePort $srcPort `
            -TargetPort $tgtPort `
            -NetworkProtocol ([string]$cmbProtocol.SelectedItem) `
            -ConnectionTimeout $timeout `
            -TrustServerCertificate ([bool]$chkTrust.Checked) `
            -GenerateSyncScript ([bool]$chkGenerate.Checked) `
            -IncludeDrops ([bool]$chkDrops.Checked) `
            -Apply ([bool]$chkApply.Checked) `
            -OutputPath $txtOutput.Text.Trim() `
            -ExcludeSchema $exclude

        Append-Log '========================================'
        Append-Log "Starting Compare-SqlSchema.ps1"
        Append-Log "Source: $srcInst / $srcDb"
        Append-Log "Target: $tgtInst"
        if ($listPath) { Append-Log "Dest list file: $listPath" }
        elseif ($targetDbs) { Append-Log "Target DB(s): $($targetDbs -join ', ')" }
        else { Append-Log "Target DB(s): (same name as source)" }
        Append-Log "Script: $($script:CompareScript)"
        Append-Log '========================================'

        Set-BusyUi $true
        Set-Status 'Running schema compare...'
        $script:LogCursor = 0
        $script:SyncHash = [hashtable]::Synchronized(@{
            Log     = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
            Results = $null
            Error   = $null
            Done    = $false
        })

        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ApartmentState = 'MTA'
        $runspace.ThreadOptions = 'ReuseThread'
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable('sync', $script:SyncHash)
        $runspace.SessionStateProxy.SetVariable('compareScript', $script:CompareScript)
        $runspace.SessionStateProxy.SetVariable('splat', $splat)

        $ps = [powershell]::Create()
        $ps.Runspace = $runspace
        [void]$ps.AddScript({
            function Write-Host {
                param(
                    [Parameter(ValueFromRemainingArguments = $true)]$Object,
                    [ConsoleColor]$ForegroundColor,
                    [ConsoleColor]$BackgroundColor,
                    [switch]$NoNewline
                )
                $msg = ($Object | ForEach-Object { "$_" }) -join ' '
                [void]$sync.Log.Add($msg)
            }
            function Write-Warning { param($Message) [void]$sync.Log.Add("WARNING: $Message") }
            try {
                $out = & $compareScript @splat
                $sync.Results = $out
            } catch {
                $sync.Error = $_.Exception.Message
                [void]$sync.Log.Add("EXCEPTION: $($_.Exception.Message)")
            } finally {
                $sync.Done = $true
            }
        })

        $script:Runspace = $runspace
        $script:PsInstance = $ps
        $script:AsyncResult = $ps.BeginInvoke()
        $pollTimer.Start()
    } catch {
        Set-BusyUi $false
        Append-Log "Cannot start: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Validation', 'OK', 'Error') | Out-Null
    }
})

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:IsBusy) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            'A compare is still running. Exit anyway?', 'Exit', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
    }
    try { Save-CurrentSettings } catch { }
})

$form.Add_Shown({
    Append-Log "Schema Compare GUI ready."
    Append-Log "Using engine: $($script:CompareScript)"
    Append-Log "Output default: $($script:DefaultOutput)"
    Load-SavedSettings
    Update-ModeUi
    Set-Status 'Ready - configure source/target, then Run compare.'
})

# Handle resize for log box
$form.Add_Resize({
    $margin = 12
    $txtLog.Width = $form.ClientSize.Width - (2 * $margin)
    $txtLog.Height = [Math]::Max(60, $form.ClientSize.Height - $txtLog.Top - $statusStrip.Height - $margin)
})

[void]$form.ShowDialog()
