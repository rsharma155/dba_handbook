# embed_scripts.ps1
# Reads all .sql files from the repository and embeds them into DBA_Production_Handbook.html

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$HtmlFile = Join-Path $ScriptDir 'DBA_Production_Handbook.html'

if (-not (Test-Path $HtmlFile)) {
    Write-Error "HTML file not found: $HtmlFile"
    exit 1
}

Write-Host "Scanning SQL scripts in: $RepoRoot" -ForegroundColor Cyan

$sqlFiles = Get-ChildItem -Path $RepoRoot -Filter '*.sql' -Recurse | Where-Object {
    $_.Name -ne '_MASTER_INDEX.sql' -and
    $_.DirectoryName -notlike '*\.vs*' -and
    $_.DirectoryName -notlike '*\.git*' -and
    $_.DirectoryName -notlike '*node_modules*' -and
    $_.DirectoryName -notlike '*output*' -and
    $_.DirectoryName -notlike '*docs*'
} | Sort-Object FullName

Write-Host "Found $($sqlFiles.Count) SQL scripts" -ForegroundColor Green

$bt = [char]96

$entries = New-Object System.Collections.ArrayList
foreach ($file in $sqlFiles) {
    $relPath = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $escaped = $content.Replace('\', '\\')
    $escaped = $escaped.Replace("$bt", "\$bt")
    $escaped = $escaped.Replace('${', ('\$' + '{'))
    $line = "  '$relPath': $bt$escaped$bt"
    [void]$entries.Add($line)
}

$joined = $entries -join ",`n"
$jsObject = "const scriptContents = {`n$joined};"

$html = [System.IO.File]::ReadAllText($HtmlFile, [System.Text.Encoding]::UTF8)

$startMarker = 'const scriptContents = {'
$endMarker = 'const scriptCatalog = ['
$startIdx = $html.IndexOf($startMarker)
$endIdx = $html.IndexOf($endMarker)

if ($startIdx -ge 0 -and $endIdx -gt $startIdx) {
    $before = $html.Substring(0, $startIdx)
    $after = $html.Substring($endIdx)
    $html = $before + $jsObject + "`n`n" + $after
    [System.IO.File]::WriteAllText($HtmlFile, $html, [System.Text.Encoding]::UTF8)
    Write-Host "Successfully embedded $($sqlFiles.Count) SQL scripts into handbook." -ForegroundColor Green
    Write-Host "Output: $HtmlFile" -ForegroundColor Yellow
} else {
    Write-Error "Could not find scriptContents pattern in the HTML file."
    exit 1
}
