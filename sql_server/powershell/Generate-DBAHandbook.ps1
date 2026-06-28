<#
.SYNOPSIS
    Generates the SQL Server DBA Production Handbook as an interactive HTML application.

.DESCRIPTION
    Creates a self-contained HTML file with:
    - 23 DBA operational sections with interactive checklists
    - LocalStorage persistence for checklist state
    - Export to PDF (print-friendly) and Excel (SheetJS)
    - Dark mode toggle
    - Global search across all sections and wait types
    - Troubleshooting Decision Trees for incident response
    - P1-P4 Incident Severity Classification Model
    - Production Safety Warning Panels before script execution
    - Evidence Collection Module with incident snapshot export
    - Time-based Daily Operational Workflow (Morning/Day/Weekly/Monthly)
    - Wait Statistics Knowledge Base (12+ wait types with meaning, cause, fix)
    - Patch Management and Data Corruption Response sections
    - Enhanced Script Explorer with environment awareness and production safety flags
    - All checklist items mapped to existing SQL scripts with absolute paths
    - Responsive design (desktop, tablet, mobile)

.PARAMETER OutputPath
    Path where the HTML file will be generated.
    Default: ..\output\DBA_Production_Handbook.html

.EXAMPLE
    .\Generate-DBAHandbook.ps1
    .\Generate-DBAHandbook.ps1 -OutputPath "C:\temp\handbook.html"
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $scriptDir = $PSScriptRoot
    $repoRoot = Split-Path $scriptDir -Parent
    $outputDir = Join-Path $repoRoot 'output'
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }
    $OutputPath = Join-Path $outputDir 'DBA_Production_Handbook.html'
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$scriptBase = '.'

Write-Host "Generating DBA Production Handbook..." -ForegroundColor Cyan
Write-Host "Repository root: $repoRoot" -ForegroundColor Gray
Write-Host "Output: $OutputPath" -ForegroundColor Gray

$html = @"
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>SQL Server DBA Production Handbook</title>

<style>
:root {
  --bg-primary: #0f1419;
  --bg-secondary: #1a1f2e;
  --bg-card: #1e2538;
  --bg-hover: #263044;
  --text-primary: #e1e5ee;
  --text-secondary: #8892a4;
  --accent: #3b82f6;
  --accent-hover: #2563eb;
  --accent-light: rgba(59,130,246,0.15);
  --success: #22c55e;
  --warning: #f59e0b;
  --danger: #ef4444;
  --border: #2d3748;
  --sidebar-width: 280px;
  --header-height: 64px;
}
[data-theme="light"] {
  --bg-primary: #f0f2f5;
  --bg-secondary: #ffffff;
  --bg-card: #ffffff;
  --bg-hover: #f5f7fa;
  --text-primary: #1a202c;
  --text-secondary: #4a5568;
  --accent: #2563eb;
  --accent-hover: #1d4ed8;
  --accent-light: rgba(37,99,235,0.08);
  --border: #e2e8f0;
}
* { margin:0; padding:0; box-sizing:border-box; }
body {
  font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
  background: var(--bg-primary);
  color: var(--text-primary);
  overflow-x: hidden;
}
.header {
  position: fixed; top:0; left:0; right:0; height: var(--header-height);
  background: var(--bg-secondary); border-bottom: 1px solid var(--border);
  display: flex; align-items: center; justify-content: space-between;
  padding: 0 24px; z-index: 1000;
}
.header-title { display:flex; align-items:center; gap:12px; }
.header-title h1 { font-size:18px; font-weight:700; white-space:nowrap; }
.header-title .subtitle { font-size:11px; color:var(--text-secondary); letter-spacing:0.5px; text-transform:uppercase; }
.header-actions { display:flex; align-items:center; gap:8px; }
.btn-icon {
  width:36px; height:36px; border-radius:8px; border:1px solid var(--border);
  background:var(--bg-card); color:var(--text-secondary); cursor:pointer;
  display:flex; align-items:center; justify-content:center; font-size:14px;
  transition: all 0.2s;
}
.btn-icon:hover { background:var(--bg-hover); color:var(--text-primary); border-color:var(--accent); }
.btn-accent {
  padding:6px 14px; border-radius:8px; border:none; background:var(--accent);
  color:#fff; cursor:pointer; font-size:13px; font-weight:500;
  display:flex; align-items:center; gap:6px; transition:all 0.2s;
}
.btn-accent:hover { background:var(--accent-hover); }
.sidebar {
  position:fixed; top:var(--header-height); left:0; bottom:0;
  width:var(--sidebar-width); background:var(--bg-secondary);
  border-right:1px solid var(--border); overflow-y:auto; z-index:900;
  transition: transform 0.3s;
}
.sidebar.collapsed { transform: translateX(calc(-1 * var(--sidebar-width))); }
.sidebar-section { padding:12px 0; }
.sidebar-section-title {
  padding:8px 20px; font-size:10px; font-weight:700;
  text-transform:uppercase; letter-spacing:1px; color:var(--text-secondary);
}
.sidebar-item {
  display:flex; align-items:center; gap:10px; padding:9px 20px;
  cursor:pointer; transition:all 0.15s; font-size:13px; color:var(--text-secondary);
  border-left:3px solid transparent;
}
.sidebar-item:hover { background:var(--bg-hover); color:var(--text-primary); }
.sidebar-item.active { background:var(--accent-light); color:var(--accent); border-left-color:var(--accent); font-weight:600; }
.sidebar-item .badge {
  margin-left:auto; font-size:10px; padding:2px 6px; border-radius:10px;
  background:var(--accent-light); color:var(--accent); font-weight:600;
}
.main-content {
  margin-left: var(--sidebar-width); margin-top: var(--header-height);
  padding:24px; min-height:calc(100vh - var(--header-height));
  transition: margin-left 0.3s;
}
.sidebar.collapsed ~ .main-content { margin-left:0; }
.section-page { display:none; }
.section-page.active { display:block; max-width:1100px; }
.page-header { margin-bottom:24px; }
.page-header h2 { font-size:24px; font-weight:700; margin-bottom:6px; }
.page-header p { color:var(--text-secondary); font-size:14px; }
.back-btn {
  display:none; align-items:center; gap:6px;
  background:var(--bg-card); border:1px solid var(--border);
  border-radius:8px; padding:8px 16px; margin-bottom:16px;
  color:var(--text-primary); font-size:14px; cursor:pointer;
  transition:background 0.2s, border-color 0.2s;
}
.back-btn:hover { background:var(--accent); color:#fff; border-color:var(--accent); }
.back-btn.visible { display:inline-flex; }
.card-box {
  background:var(--bg-card); border:1px solid var(--border);
  border-radius:12px; padding:20px; margin-bottom:16px;
}
.card-box h3 { font-size:16px; font-weight:600; margin-bottom:12px; display:flex; align-items:center; gap:8px; }
.card-box h3 i { color:var(--accent); font-size:14px; }
.checklist-item {
  display:flex; align-items:flex-start; gap:10px; padding:10px 0;
  border-bottom:1px solid var(--border);
}
.checklist-item:last-child { border-bottom:none; }
.checklist-item input[type="checkbox"] {
  width:18px; height:18px; margin-top:2px; accent-color:var(--accent);
  cursor:pointer; flex-shrink:0;
}
.checklist-item .item-content { flex:1; }
.checklist-item .item-text { font-size:14px; line-height:1.5; }
.checklist-item .item-script {
  display:inline-flex; align-items:center; gap:4px; margin-top:4px;
  font-size:11px; color:var(--accent); background:var(--accent-light);
  padding:2px 8px; border-radius:4px; font-family:'Cascadia Code','Consolas',monospace;
  cursor:pointer; transition:all 0.2s; border:1px solid transparent;
  position:relative;
}
.checklist-item .item-script:hover { background:var(--accent); color:#fff; border-color:var(--accent); }
.checklist-item .item-script::after {
  content:'\2197'; font-size:8px; margin-left:2px; opacity:0.6;
}
.checklist-item .item-script:hover::after { opacity:1; }
.checklist-item .item-script i { font-size:10px; }
.checklist-item .item-meta {
  margin-top:4px; font-size:11px; color:var(--text-secondary);
}
.priority-badge {
  display:inline-block; font-size:10px; font-weight:600; padding:2px 8px;
  border-radius:4px; text-transform:uppercase; letter-spacing:0.3px;
}
.priority-critical { background:rgba(239,68,68,0.15); color:var(--danger); }
.priority-high { background:rgba(245,158,11,0.15); color:var(--warning); }
.priority-medium { background:rgba(59,130,246,0.15); color:var(--accent); }
.priority-low { background:rgba(34,197,94,0.15); color:var(--success); }
table.data-table {
  width:100%; border-collapse:collapse; font-size:13px;
}
table.data-table th {
  background:var(--bg-hover); padding:10px 12px; text-align:left;
  font-weight:600; font-size:11px; text-transform:uppercase;
  letter-spacing:0.5px; color:var(--text-secondary);
  border-bottom:2px solid var(--border);
}
table.data-table td {
  padding:10px 12px; border-bottom:1px solid var(--border);
  vertical-align:top;
}
table.data-table tr:hover td { background:var(--bg-hover); }
.script-path {
  font-family:'Cascadia Code','Consolas',monospace; font-size:11px;
  color:var(--accent); word-break:break-all;
}
.search-overlay {
  display:none; position:fixed; inset:0; background:rgba(0,0,0,0.6);
  z-index:2000; align-items:flex-start; justify-content:center; padding-top:100px;
}
.search-overlay.active { display:flex; }
.search-box {
  width:600px; max-width:90vw; background:var(--bg-card); border-radius:12px;
  border:1px solid var(--border); overflow:hidden;
}
.search-box input {
  width:100%; padding:16px 20px; border:none; background:transparent;
  color:var(--text-primary); font-size:16px; outline:none;
}
.search-results { max-height:400px; overflow-y:auto; padding:8px; }
.search-result-item {
  padding:10px 12px; border-radius:8px; cursor:pointer; font-size:13px;
}
.search-result-item:hover { background:var(--bg-hover); }
.search-result-item .sr-section { font-size:11px; color:var(--accent); }
.progress-bar-container {
  height:6px; background:var(--border); border-radius:3px; overflow:hidden; margin-top:8px;
}
.progress-bar-fill {
  height:100%; background:linear-gradient(90deg,var(--accent),var(--success));
  border-radius:3px; transition:width 0.5s;
}
.dashboard-cards { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:16px; margin-bottom:24px; }
.dash-card {
  background:var(--bg-card); border:1px solid var(--border); border-radius:12px;
  padding:20px;
}
.dash-card h4 { font-size:14px; color:var(--text-secondary); margin-bottom:12px; }
.dash-card .big-number { font-size:36px; font-weight:700; color:var(--accent); }
.dash-card .big-label { font-size:12px; color:var(--text-secondary); }
.flow-steps { display:flex; flex-direction:column; gap:0; align-items:center; }
.flow-step {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:12px 20px; font-size:13px; font-weight:500; width:300px; text-align:center;
  position:relative;
}
.flow-arrow {
  width:2px; height:24px; background:var(--accent); position:relative;
}
.flow-arrow::after {
  content:''; position:absolute; bottom:-4px; left:-4px;
  border-left:5px solid transparent; border-right:5px solid transparent;
  border-top:6px solid var(--accent);
}
.notes-field {
  width:100%; padding:8px 12px; border:1px solid var(--border);
  border-radius:6px; background:var(--bg-hover); color:var(--text-primary);
  font-size:12px; resize:vertical; min-height:36px; margin-top:6px;
}
.tag { display:inline-block; font-size:10px; padding:2px 6px; border-radius:4px; margin-right:4px; margin-top:4px; }
.tag-r { background:rgba(239,68,68,0.15); color:var(--danger); }
.tag-y { background:rgba(245,158,11,0.15); color:var(--warning); }
.tag-g { background:rgba(34,197,94,0.15); color:var(--success); }
.tag-b { background:rgba(59,130,246,0.15); color:var(--accent); }
.collapsible-trigger {
  cursor:pointer; display:flex; align-items:center; justify-content:space-between;
}
.collapsible-trigger i { transition:transform 0.2s; font-size:12px; color:var(--text-secondary); }
.collapsible-trigger.open i { transform:rotate(90deg); }
.collapsible-body { overflow:hidden; max-height:0; transition:max-height 0.3s ease; }
.collapsible-body.open { max-height:5000px; }

.severity-p1 { background:rgba(239,68,68,0.2); color:#ef4444; border:1px solid rgba(239,68,68,0.3); }
.severity-p2 { background:rgba(245,158,11,0.2); color:#f59e0b; border:1px solid rgba(245,158,11,0.3); }
.severity-p3 { background:rgba(59,130,246,0.15); color:#3b82f6; border:1px solid rgba(59,130,246,0.2); }
.severity-p4 { background:rgba(34,197,94,0.12); color:#22c55e; border:1px solid rgba(34,197,94,0.2); }
.severity-badge {
  display:inline-block; font-size:11px; font-weight:700; padding:3px 10px;
  border-radius:6px; text-transform:uppercase; letter-spacing:0.5px;
}
.safety-panel {
  background:linear-gradient(135deg, rgba(245,158,11,0.08), rgba(239,68,68,0.08));
  border:1px solid var(--warning); border-radius:10px; padding:16px 20px; margin:12px 0;
}
.safety-panel h4 { color:var(--warning); font-size:14px; margin-bottom:10px; display:flex; align-items:center; gap:8px; }
.safety-checklist { display:grid; grid-template-columns:repeat(auto-fit,minmax(250px,1fr)); gap:8px; }
.safety-check-item {
  display:flex; align-items:center; gap:8px; font-size:13px; color:var(--text-primary);
  padding:6px 10px; background:var(--bg-hover); border-radius:6px;
}
.env-badge {
  display:inline-block; font-size:9px; font-weight:700; padding:2px 6px;
  border-radius:4px; text-transform:uppercase; letter-spacing:0.3px; margin-left:4px;
}
.env-prod { background:rgba(239,68,68,0.15); color:var(--danger); }
.env-uat { background:rgba(245,158,11,0.15); color:var(--warning); }
.env-dev { background:rgba(34,197,94,0.15); color:var(--success); }
.env-dr { background:rgba(59,130,246,0.15); color:var(--accent); }
.decision-tree-wrapper {
  overflow:auto; border:1px solid var(--border); border-radius:10px;
  padding:20px; background:var(--bg-primary); max-height:700px;
  position:relative;
}
.dt-legend {
  display:flex; gap:16px; margin-bottom:16px; font-size:12px; color:var(--text-secondary);
  flex-wrap:wrap;
}
.dt-legend span { display:flex; align-items:center; gap:4px; }
.dt-legend .dt-legend-dot {
  width:12px; height:12px; border-radius:4px; display:inline-block;
}
.decision-tree { padding:16px 0; min-width:1100px; }
.dt-level { display:flex; flex-direction:column; align-items:center; width:100%; }
.dt-node {
  background:var(--bg-card); border:2px solid var(--border); border-radius:10px;
  padding:12px 16px; margin:6px auto; width:240px; text-align:center;
  font-size:13px; font-weight:500; position:relative; box-sizing:border-box;
}
.dt-node.question { border-color:var(--accent); background:var(--accent-light); }
.dt-node.action { border-color:var(--success); background:rgba(34,197,94,0.08); }
.dt-node.script { border-color:var(--warning); background:rgba(245,158,11,0.08); font-family:'Cascadia Code','Consolas',monospace; font-size:11px; padding:8px 12px; width:auto; min-width:200px; max-width:420px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.dt-branch { display:flex; justify-content:center; gap:32px; margin:4px 0; width:100%; }
.dt-branch-label { font-size:11px; font-weight:700; padding:3px 10px; border-radius:12px; display:inline-block; }
.dt-yes { background:rgba(34,197,94,0.15); color:var(--success); }
.dt-no { background:rgba(239,68,68,0.15); color:var(--danger); }
.dt-connector { width:2px; height:14px; background:var(--border); margin:0 auto; }
.dt-connector-h { height:2px; background:var(--border); margin:4px auto; }
.dt-arm { flex:1; max-width:480px; display:flex; flex-direction:column; align-items:center; }
.evidence-card {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:16px 20px; margin-bottom:12px;
}
.evidence-card h4 { font-size:14px; font-weight:600; margin-bottom:10px; display:flex; align-items:center; gap:8px; }
.evidence-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr)); gap:8px; }
.evidence-item {
  padding:8px 12px; background:var(--bg-hover); border-radius:6px; font-size:13px;
  display:flex; align-items:center; gap:8px;
}
.evidence-item label { font-weight:500; min-width:120px; color:var(--text-secondary); }
.time-workflow { display:grid; gap:16px; }
.time-slot {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:16px 20px; display:flex; gap:16px; align-items:flex-start;
}
.time-badge {
  min-width:90px; padding:8px 12px; border-radius:8px; text-align:center;
  font-size:12px; font-weight:700; flex-shrink:0;
}
.time-morning { background:rgba(245,158,11,0.15); color:var(--warning); }
.time-daytime { background:rgba(59,130,246,0.15); color:var(--accent); }
.time-weekly { background:rgba(168,85,247,0.15); color:#a855f7; }
.time-monthly { background:rgba(34,197,94,0.15); color:var(--success); }
.time-content { flex:1; }
.time-content h4 { font-size:14px; font-weight:600; margin-bottom:6px; }
.time-content ul { margin:0; padding-left:18px; font-size:13px; color:var(--text-secondary); }
.time-content li { margin-bottom:3px; }
.kb-card {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:16px 20px; margin-bottom:12px; transition:border-color 0.2s;
}
.kb-card:hover { border-color:var(--accent); }
.kb-card h4 { font-size:15px; font-weight:600; margin-bottom:8px; color:var(--accent); }
.kb-field { margin-bottom:6px; font-size:13px; }
.kb-field strong { color:var(--text-secondary); min-width:100px; display:inline-block; }
.enhanced-checklist {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:16px 20px; margin-bottom:12px; transition:border-color 0.2s;
}
.enhanced-checklist:hover { border-color:var(--accent); }
.enhanced-checklist .ec-header {
  display:flex; align-items:flex-start; gap:10px; margin-bottom:10px;
}
.enhanced-checklist .ec-header input[type="checkbox"] {
  width:18px; height:18px; margin-top:2px; accent-color:var(--accent); cursor:pointer; flex-shrink:0;
}
.enhanced-checklist .ec-title { font-size:14px; font-weight:500; flex:1; }
.enhanced-checklist .ec-details {
  display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:8px;
  margin-left:28px; font-size:12px; color:var(--text-secondary);
}
.enhanced-checklist .ec-detail { display:flex; align-items:center; gap:6px; }
.enhanced-checklist .ec-detail strong { min-width:70px; }
.global-search-bar {
  display:flex; align-items:center; gap:8px; padding:6px 14px;
  border:1px solid var(--border); border-radius:8px; background:var(--bg-card);
  color:var(--text-secondary); font-size:13px; cursor:pointer; transition:all 0.2s;
}
.global-search-bar:hover { border-color:var(--accent); color:var(--text-primary); }
.global-search-bar input {
  border:none; background:transparent; color:var(--text-primary);
  font-size:13px; outline:none; width:180px;
}
.patch-card {
  background:var(--bg-card); border:1px solid var(--border); border-radius:10px;
  padding:16px 20px; margin-bottom:12px;
}
.patch-card h4 { font-size:14px; font-weight:600; margin-bottom:8px; display:flex; align-items:center; gap:8px; }
.corruption-step {
  display:flex; gap:12px; align-items:flex-start; padding:12px 0;
  border-bottom:1px solid var(--border);
}
.corruption-step:last-child { border-bottom:none; }
.corruption-num {
  width:28px; height:28px; border-radius:50%; background:var(--accent);
  color:#fff; display:flex; align-items:center; justify-content:center;
  font-size:13px; font-weight:700; flex-shrink:0;
}

.dbamode-toggle {
  display:flex; align-items:center; gap:6px; font-size:12px; color:var(--text-secondary);
}
.dbamode-switch {
  position:relative; width:40px; height:22px; background:var(--border); border-radius:11px;
  cursor:pointer; transition:background 0.3s;
}
.dbamode-switch.active { background:var(--accent); }
.dbamode-switch::after {
  content:''; position:absolute; top:2px; left:2px; width:18px; height:18px;
  background:#fff; border-radius:50%; transition:transform 0.3s;
}
.dbamode-switch.active::after { transform:translateX(18px); }
.dbamode-label { font-weight:600; }
.senior-only { display:none; } /* hidden in Junior mode, shown in Senior mode */
body.mode-senior .senior-only { display:block; }
body.mode-senior .senior-only-flex { display:flex; }

.version-tag {
  display:inline-block; font-size:9px; font-weight:700; padding:2px 5px;
  border-radius:3px; text-transform:uppercase; letter-spacing:0.3px;
  background:rgba(168,85,247,0.15); color:#a855f7; margin-left:4px;
}
.risk-safe { background:rgba(34,197,94,0.15); color:var(--success); }
.risk-caution { background:rgba(245,158,11,0.15); color:var(--warning); }
.risk-restricted { background:rgba(239,68,68,0.15); color:var(--danger); }

.safety-panel-enhanced {
  background:linear-gradient(135deg, rgba(245,158,11,0.08), rgba(239,68,68,0.08));
  border:1px solid var(--warning); border-radius:10px; padding:16px 20px; margin:12px 0;
}
.safety-panel-enhanced h4 { color:var(--warning); font-size:14px; margin-bottom:10px; display:flex; align-items:center; gap:8px; }
.safety-checklist-enhanced { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:8px; }
.safety-check-item-enhanced {
  display:flex; align-items:center; gap:10px; font-size:13px; color:var(--text-primary);
  padding:8px 12px; background:var(--bg-hover); border-radius:6px;
}
.safety-check-item-enhanced input[type="checkbox"] {
  width:16px; height:16px; accent-color:var(--warning); cursor:pointer; flex-shrink:0;
}

.env-profile-grid {
  display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:12px;
}
.env-profile-field {
  display:flex; flex-direction:column; gap:4px;
}
.env-profile-field label {
  font-size:12px; font-weight:600; color:var(--text-secondary); text-transform:uppercase; letter-spacing:0.3px;
}
.env-profile-field input, .env-profile-field select {
  padding:8px 12px; border:1px solid var(--border); border-radius:6px;
  background:var(--bg-hover); color:var(--text-primary); font-size:13px;
}

.change-checklist-grid {
  display:grid; grid-template-columns:repeat(auto-fit,minmax(300px,1fr)); gap:16px;
}
.change-checklist-col h4 {
  font-size:14px; font-weight:600; margin-bottom:10px; display:flex; align-items:center; gap:8px;
}

.automation-level {
  display:flex; gap:16px; align-items:stretch; flex-wrap:wrap; margin-top:12px;
}
.auto-level-card {
  flex:1; min-width:200px; background:var(--bg-card); border:1px solid var(--border);
  border-radius:10px; padding:16px; text-align:center; transition:border-color 0.2s;
}
.auto-level-card:hover { border-color:var(--accent); }
.auto-level-card .level-num {
  font-size:28px; font-weight:700; color:var(--accent); margin-bottom:4px;
}
.auto-level-card .level-name {
  font-size:13px; font-weight:600; margin-bottom:6px;
}
.auto-level-card .level-desc {
  font-size:12px; color:var(--text-secondary); line-height:1.4;
}

.evidence-checkbox-grid {
  display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:8px; margin-top:12px;
}
.evidence-check-item {
  display:flex; align-items:center; gap:8px; font-size:13px; padding:6px 10px;
  background:var(--bg-hover); border-radius:6px;
}
.evidence-check-item input[type="checkbox"] {
  width:16px; height:16px; accent-color:var(--accent); cursor:pointer; flex-shrink:0;
}

/* Script Viewer Modal */
.script-viewer-overlay {
  display:none; position:fixed; inset:0; background:rgba(0,0,0,0.7);
  z-index:3000; align-items:center; justify-content:center; padding:20px;
}
.script-viewer-overlay.active { display:flex; }
.script-viewer {
  width:95vw; max-width:1200px; max-height:90vh; background:var(--bg-card);
  border:1px solid var(--border); border-radius:12px; display:flex;
  flex-direction:column; overflow:hidden;
}
.script-viewer-header {
  display:flex; align-items:center; justify-content:space-between;
  padding:14px 20px; border-bottom:1px solid var(--border);
  background:var(--bg-secondary); flex-shrink:0;
}
.script-viewer-header h3 { font-size:15px; font-weight:600; display:flex; align-items:center; gap:8px; margin:0; }
.script-viewer-actions { display:flex; gap:6px; align-items:center; }
.script-viewer-body { flex:1; overflow:auto; padding:0; }
.sql-code {
  margin:0; padding:16px 20px; font-family:'Cascadia Code','Fira Code','Consolas',monospace;
  font-size:13px; line-height:1.65; white-space:pre; overflow:auto;
  background:#1e1e1e; color:#d4d4d4; tab-size:4;
}
.copy-btn {
  padding:4px 10px; border-radius:6px; border:1px solid var(--border);
  background:var(--bg-hover); color:var(--text-secondary); cursor:pointer;
  font-size:11px; display:flex; align-items:center; gap:4px; transition:all 0.2s;
}
.copy-btn:hover { background:var(--accent); color:#fff; border-color:var(--accent); }
.sql-cmt { color:#6a9955; font-style:italic; }
.sql-str { color:#ce9178; }
.sql-num { color:#b5cea8; }
.sql-kw { color:#569cd6; font-weight:600; }
.sql-fn { color:#dcdcaa; }
.sql-dmv { color:#4ec9b0; }
.sql-type { color:#4ec9b0; }
.sql-var { color:#9cdcfe; }

@media print {
  .header,.sidebar,.search-overlay,.btn-icon,.btn-accent,.no-print { display:none!important; }
  .main-content { margin:0!important; padding:10px!important; }
  .section-page { display:block!important; page-break-before:always; }
  .section-page:first-child { page-break-before:auto; }
  body { background:#fff!important; color:#000!important; }
  .card-box,.dash-card { border-color:#ccc!important; background:#fff!important; break-inside:avoid; }
  .checklist-item input[type="checkbox"] { -webkit-print-color-adjust:exact; print-color-adjust:exact; }
}

@media(max-width:768px) {
  .sidebar { transform:translateX(calc(-1 * var(--sidebar-width))); }
  .sidebar.mobile-open { transform:translateX(0); }
  .main-content { margin-left:0; }
  .header-title .subtitle { display:none; }
  .header-title h1 { font-size:14px; }
  .script-viewer { width:100vw; max-height:100vh; border-radius:0; }
  .script-viewer-header { padding:8px 12px; }
  .script-viewer-header h3 { font-size:12px; }
  .sql-code { font-size:11px; padding:10px 12px; }
  .copy-btn { padding:3px 8px; font-size:10px; }
}

.sidebar::-webkit-scrollbar, .main-content::-webkit-scrollbar { width:6px; }
.sidebar::-webkit-scrollbar-thumb, .main-content::-webkit-scrollbar-thumb { background:var(--border); border-radius:3px; }
i[class*="fas fa-"]::before { display:inline-block; font-style:normal; font-weight:normal; }
i.fas::before { content:""; }
i.fas.fa-bars::before { content:"\2630"; }
i.fas.fa-database::before { content:"\1F5C4"; }
i.fas.fa-search::before { content:"\1F50D"; }
i.fas.fa-moon::before { content:"\1F319"; }
i.fas.fa-sun::before { content:"\2600"; }
i.fas.fa-file-excel::before { content:"\1F4CA"; }
i.fas.fa-file-pdf::before { content:"\1F4C4"; }
i.fas.fa-th-large::before { content:"\25A6"; }
i.fas.fa-compass::before { content:"\27A1"; }
i.fas.fa-first-aid::before { content:"\2764"; }
i.fas.fa-map-marked-alt::before { content:"\1F4CD"; }
i.fas.fa-cogs::before { content:"\2699"; }
i.fas.fa-heartbeat::before { content:"\2764"; }
i.fas.fa-desktop::before { content:"\1F5A5"; }
i.fas.fa-bolt::before { content:"\26A1"; }
i.fas.fa-tachometer-alt::before { content:"\25D4"; }
i.fas.fa-lock::before { content:"\1F512"; }
i.fas.fa-scroll::before { content:"\1F4DC"; }
i.fas.fa-shield-alt::before { content:"\1F6E1"; }
i.fas.fa-user-shield::before { content:"\1F6E1"; }
i.fas.fa-network-wired::before { content:"\1F310"; }
i.fas.fa-life-ring::before { content:"\2B55"; }
i.fas.fa-chart-line::before { content:"\1F4C8"; }
i.fas.fa-exchange-alt::before { content:"\21C4"; }
i.fas.fa-robot::before { content:"\1F916"; }
i.fas.fa-book-open::before { content:"\1F4D6"; }
i.fas.fa-clipboard-list::before { content:"\1F4CB"; }
i.fas.fa-road::before { content:"\1F6E3"; }
i.fas.fa-folder-open::before { content:"\1F4C2"; }
i.fas.fa-check-circle::before { content:"\2705"; }
i.fas.fa-layer-group::before { content:"\25B3"; }
i.fas.fa-rocket::before { content:"\1F680"; }
i.fas.fa-list-check::before { content:"\2611"; }
i.fas.fa-exclamation-triangle::before { content:"\26A0"; }
i.fas.fa-file-code::before { content:"\1F4C3"; }
i.fas.fa-window-maximize::before { content:"\25A1"; }
i.fas.fa-code::before { content:"\207D"; }
i.fas.fa-server::before { content:"\1F5A5"; }
i.fas.fa-microchip::before { content:"\1F9E0"; }
i.fas.fa-power-off::before { content:"\23FB"; }
i.fas.fa-hand-paper::before { content:"\270B"; }
i.fas.fa-sliders-h::before { content:"\2630"; }
i.fas.fa-memory::before { content:"\1F9E0"; }
i.fas.fa-divide::before { content:"\00F7"; }
i.fas.fa-compact-disc::before { content:"\1F3B5"; }
i.fas.fa-clock::before { content:"\23F0"; }
i.fas.fa-bell::before { content:"\1F514"; }
i.fas.fa-clipboard-check::before { content:"\2705"; }
i.fas.fa-crosshairs::before { content:"\2295"; }
i.fas.fa-wrench::before { content:"\1F527"; }
i.fas.fa-file-alt::before { content:"\1F4C4"; }
i.fas.fa-check-double::before { content:"\2705"; }
i.fas.fa-crown::before { content:"\1F451"; }
i.fas.fa-seedling::before { content:"\1F331"; }
i.fas.fa-user-tie::before { content:"\1F468"; }
i.fas.fa-expand-arrows-alt::before { content:"\21D5"; }
i.fas.fa-times::before { content:"\00D7"; }
i.fas.fa-undo::before { content:"\21BA"; }
</style>
</head>
<body class="mode-junior">

<div class="header">
  <div class="header-title">
    <button class="btn-icon no-print" onclick="toggleSidebar()" title="Toggle sidebar"><i class="fas fa-bars"></i></button>
    <div>
      <h1><i class="fas fa-database" style="color:var(--accent)"></i> SQL Server DBA Production Handbook</h1>
      <div class="subtitle">Operations &bull; Troubleshooting &bull; Incident Response</div>
    </div>
  </div>
  <div class="header-actions no-print">
    <div class="global-search-bar" onclick="openSearch()">
      <i class="fas fa-search"></i>
      <input type="text" placeholder="Search scripts, waits, blocks..." readonly onclick="openSearch()">
      <span style="font-size:10px;padding:2px 6px;border-radius:4px;border:1px solid var(--border);color:var(--text-secondary);">Ctrl+K</span>
    </div>
    <div class="dbamode-toggle" title="Toggle Junior/Senior DBA mode">
      <span class="dbamode-label" id="modeLabel">Junior</span>
      <div class="dbamode-switch" id="dbamodeSwitch" onclick="toggleDBAMode()"></div>
      <span class="dbamode-label" id="modeLabelSenior" style="color:var(--text-secondary)">Senior</span>
    </div>
    <button class="btn-icon" onclick="toggleTheme()" title="Toggle theme" id="themeBtn"><i class="fas fa-moon"></i></button>
    <button class="btn-icon" onclick="resetHandbook()" title="Reset all checklist progress" style="color:var(--danger);border-color:var(--danger);"><i class="fas fa-undo"></i></button>
    <button class="btn-accent" onclick="exportExcel()" title="Export to Excel"><i class="fas fa-file-excel"></i> Excel</button>
    <button class="btn-accent" onclick="window.print()" title="Export to PDF"><i class="fas fa-file-pdf"></i> PDF</button>
  </div>
</div>

<div class="sidebar" id="sidebar">
  <div class="sidebar-section">
    <div class="sidebar-section-title">Overview</div>
    <div class="sidebar-item active" onclick="showPage('dashboard')"><i class="fas fa-th-large"></i> Dashboard<span class="badge" id="progressBadge">0%</span></div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Core Operations</div>
    <div class="sidebar-item" onclick="showPage('sec01')"><i class="fas fa-compass"></i> 01. DBA Principles</div>
    <div class="sidebar-item" onclick="showPage('sec02')"><i class="fas fa-first-aid"></i> 02. First Responder</div>
    <div class="sidebar-item" onclick="showPage('sec03')"><i class="fas fa-map-marked-alt"></i> 03. Environment Discovery</div>
    <div class="sidebar-item" onclick="showPage('sec04')"><i class="fas fa-cogs"></i> 04. SQL Configuration</div>
    <div class="sidebar-item" onclick="showPage('sec05')"><i class="fas fa-heartbeat"></i> 05. Daily Health Checks</div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Monitoring & Response</div>
    <div class="sidebar-item" onclick="showPage('sec06')"><i class="fas fa-desktop"></i> 06. Monitoring Checklist</div>
    <div class="sidebar-item" onclick="showPage('sec07')"><i class="fas fa-bolt"></i> 07. Incident Response</div>
    <div class="sidebar-item" onclick="showPage('sec08')"><i class="fas fa-tachometer-alt"></i> 08. Performance Tuning</div>
    <div class="sidebar-item" onclick="showPage('sec09')"><i class="fas fa-lock"></i> 09. Blocking & Deadlocks</div>
    <div class="sidebar-item" onclick="showPage('sec10')"><i class="fas fa-scroll"></i> 10. Transaction Log</div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Protection & Security</div>
    <div class="sidebar-item" onclick="showPage('sec11')"><i class="fas fa-shield-alt"></i> 11. Backup & Recovery</div>
    <div class="sidebar-item" onclick="showPage('sec12')"><i class="fas fa-user-shield"></i> 12. Security Audit</div>
    <div class="sidebar-item" onclick="showPage('sec13')"><i class="fas fa-network-wired"></i> 13. High Availability</div>
    <div class="sidebar-item" onclick="showPage('sec14')"><i class="fas fa-life-ring"></i> 14. Disaster Recovery</div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Strategy</div>
    <div class="sidebar-item" onclick="showPage('sec15')"><i class="fas fa-chart-line"></i> 15. Capacity Planning</div>
    <div class="sidebar-item" onclick="showPage('sec16')"><i class="fas fa-exchange-alt"></i> 16. Change Management</div>
    <div class="sidebar-item" onclick="showPage('sec17')"><i class="fas fa-robot"></i> 17. Automation Scripts</div>
    <div class="sidebar-item" onclick="showPage('sec21')"><i class="fas fa-wrench"></i> 21. Patch Management</div>
    <div class="sidebar-item" onclick="showPage('sec22')"><i class="fas fa-exclamation-triangle"></i> 22. Data Corruption</div>
    <div class="sidebar-item" onclick="showPage('sec23')"><i class="fas fa-wave-square"></i> 23. Wait Stats Reference</div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Incident Response</div>
    <div class="sidebar-item" onclick="showPage('sec18')"><i class="fas fa-book-open"></i> 18. Case Studies</div>
    <div class="sidebar-item" onclick="showPage('sec19')"><i class="fas fa-clipboard-list"></i> 19. RCA Templates</div>
    <div class="sidebar-item" onclick="showPage('sec20')"><i class="fas fa-road"></i> 20. DBA Growth Path</div>
  </div>
  <div class="sidebar-section">
    <div class="sidebar-section-title">Reference</div>
    <div class="sidebar-item" onclick="showPage('scriptExplorer')"><i class="fas fa-folder-open"></i> Script Explorer</div>
  </div>
</div>

<div class="main-content" id="mainContent">

<button class="back-btn" id="backBtn" onclick="showPage('dashboard')"><i class="fas fa-arrow-left"></i> Back to Dashboard</button>

<!-- ==================== DASHBOARD ==================== -->
<div class="section-page active" id="page-dashboard">
  <div class="page-header">
    <h2>DBA Operations Dashboard</h2>
    <p>Real-time overview of your DBA handbook progress and key operational areas.</p>
  </div>
  <div class="dashboard-cards">
    <div class="dash-card">
      <h4><i class="fas fa-check-circle" style="color:var(--success)"></i> Checklist Progress</h4>
      <div class="big-number" id="dashProgress">0%</div>
      <div class="big-label"><span id="dashCompleted">0</span> of <span id="dashTotal">0</span> tasks completed</div>
      <div class="progress-bar-container"><div class="progress-bar-fill" id="dashProgressBar" style="width:0%"></div></div>
    </div>
    <div class="dash-card">
      <h4><i class="fas fa-database" style="color:var(--accent)"></i> Scripts Mapped</h4>
      <div class="big-number" id="dashScripts">68</div>
      <div class="big-label">SQL scripts across all categories</div>
    </div>
    <div class="dash-card">
      <h4><i class="fas fa-layer-group" style="color:var(--warning)"></i> Sections Covered</h4>
      <div class="big-number">23</div>
      <div class="big-label">Operational areas with checklists</div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-rocket"></i> Quick Actions</h3>
    <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:8px;">
      <button class="btn-accent" onclick="showPage('sec05',true)"><i class="fas fa-heartbeat"></i> Daily Health Check</button>
      <button class="btn-accent" onclick="showPage('sec07',true)"><i class="fas fa-bolt"></i> Incident Response</button>
      <button class="btn-accent" onclick="showPage('sec04',true)"><i class="fas fa-cogs"></i> Review Configuration</button>
      <button class="btn-accent" onclick="showPage('sec11',true)"><i class="fas fa-shield-alt"></i> Backup Validation</button>
      <button class="btn-accent" onclick="showPage('sec08')"><i class="fas fa-tachometer-alt"></i> Performance Analysis</button>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-list-check"></i> Section Progress</h3>
    <div id="sectionProgressList"></div>
  </div>
</div>

<!-- ==================== SEC 01: DBA PRINCIPLES ==================== -->
<div class="section-page" id="page-sec01">
  <div class="page-header">
    <h2>01. DBA Principles & Production Rules</h2>
    <p>The foundational mindset for production database administration.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-exclamation-triangle"></i> The First Rule of Production DBA</h3>
    <p style="margin-bottom:12px;font-size:14px;">Before changing anything, <strong>collect evidence</strong>. Never immediately restart, kill, shrink, or change configuration without understanding the situation.</p>
    <div class="checklist-item">
      <input type="checkbox" data-id="p01_01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>Never immediately:</strong> Restart SQL Server, Kill sessions, Shrink databases, Rebuild all indexes, Change configuration, Increase memory, Restart server</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="p01_02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>First capture:</strong> What happened? When did it start? Who reported it? What changed? Is it affecting CPU, Memory, Disk, Network, SQL workload, or Application?</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="p01_03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>Evidence collection:</strong> Always gather DMV snapshots, wait stats, and execution plans before making any changes.</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/wait_statistics.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-layer-group"></i> The 5-Layer Diagnostic Model</h3>
    <p style="margin-bottom:12px;font-size:14px;">When a problem arrives, never assume SQL Server is the problem. Investigate each layer:</p>
    <div class="flow-steps">
      <div class="flow-step"><i class="fas fa-window-maximize"></i> Application Layer</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-code"></i> SQL Query Layer</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-database"></i> SQL Engine Layer</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-server"></i> Operating System Layer</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-microchip"></i> Hardware Layer</div>
    </div>
  </div>
</div>

<!-- ==================== SEC 02: FIRST RESPONDER ==================== -->
<div class="section-page" id="page-sec02">
  <div class="page-header">
    <h2>02. First Responder Checklist</h2>
    <p>Step-by-step triage when "the database is slow" alert fires at 2 AM.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-power-off"></i> Step 1: Is SQL Server Alive?</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Can I connect to SQL Server?</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT @@SERVERNAME, @@VERSION, GETDATE();</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Service is running</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Agent is running</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Cluster status is healthy</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Availability Group status is healthy</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/alwayson_ag_monitor.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-heartbeat"></i> Step 2: Check Overall Health</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run comprehensive health check</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_HealthCheck.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check for unexpected restart, memory changes, CPU configuration changes</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/cpu_utilization.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr08" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check memory diagnostics</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/memory_diagnostics.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr09" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check disk latency</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/disk_latency.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-hand-paper"></i> Step 3: Check Current Blocking</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr10" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Identify blocking sessions</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_ActiveSessions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr11" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze blocking and deadlock patterns</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/blocking_and_deadlocks.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr12" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Questions: Who is blocking? What is the blocker doing? Is it safe to kill?</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-search"></i> Step 4: Check Running Queries</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr13" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Find top resource-consuming queries</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/top_resource_queries.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr14" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Look for: Long running queries, Massive reads, Large writes, Bad plans</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="fr15" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze wait statistics to identify bottleneck</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_WaitAnalysis.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 03: ENVIRONMENT DISCOVERY ==================== -->
<div class="section-page" id="page-sec03">
  <div class="page-header">
    <h2>03. Production Environment Discovery</h2>
    <p>Essential knowledge when joining a new organization or taking over a new environment.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-server"></i> Production Environment Profile</h3>
    <p style="margin-bottom:12px;font-size:13px;color:var(--text-secondary);">Fill this out first when taking over a new environment.</p>
    <div class="env-profile-grid">
      <div class="env-profile-field"><label>Server Name</label><input type="text" placeholder="e.g. SQLPROD01"></div>
      <div class="env-profile-field"><label>Instance Name</label><input type="text" placeholder="e.g. MSSQLSERVER"></div>
      <div class="env-profile-field"><label>SQL Version</label>
        <select><option>2016</option><option>2017</option><option>2019</option><option>2022</option><option>Azure SQL</option></select>
      </div>
      <div class="env-profile-field"><label>Edition</label>
        <select><option>Enterprise</option><option>Standard</option><option>Developer</option><option>Express</option></select>
      </div>
      <div class="env-profile-field"><label>CPU</label><input type="text" placeholder="e.g. 16 cores"></div>
      <div class="env-profile-field"><label>Memory</label><input type="text" placeholder="e.g. 128 GB"></div>
      <div class="env-profile-field"><label>Storage</label><input type="text" placeholder="e.g. SSD, 2TB"></div>
      <div class="env-profile-field"><label>HA Configuration</label>
        <select><option>None</option><option>AlwaysOn AG</option><option>Failover Cluster</option><option>Log Shipping</option><option>Replication</option></select>
      </div>
      <div class="env-profile-field"><label>Backup Location</label><input type="text" placeholder="e.g. \\backup\sqlprod"></div>
      <div class="env-profile-field"><label>Monitoring Tool</label><input type="text" placeholder="e.g. SQL Monitor"></div>
      <div class="env-profile-field"><label>Environment Type</label>
        <select><option>Production</option><option>UAT</option><option>Development</option><option>DR</option></select>
      </div>
      <div class="env-profile-field"><label>Owner / Team</label><input type="text" placeholder="e.g. DBA Team"></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-database"></i> Database Inventory</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Map all databases: Size, Recovery model, Compatibility level, Owner</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_HealthCheck.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Document Criticality, RPO/RTO requirements, Backup strategy per database</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check database compatibility levels</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 02_Instance_Config/database_compatibility_audit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Audit OS integration checks</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 02_Instance_Config/os_integration_checks.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-file-code"></i> Required Documentation</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed05" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Server inventory documented</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Database inventory documented</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Backup policy documented</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Recovery document created</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed09" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Monitoring dashboard configured</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed10" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Escalation matrix documented</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed11" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Maintenance window defined</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ed12" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Architecture diagram created</div></div>
    </div>
  </div>
</div>

<!-- ==================== SEC 04: SQL CONFIGURATION ==================== -->
<div class="section-page" id="page-sec04">
  <div class="page-header">
    <h2>04. SQL Server Configuration Checklist</h2>
    <p>Validate critical configuration settings that directly impact performance and stability.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-sliders-h"></i> Configuration Audit</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run full server configuration audit</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 02_Instance_Config/server_configuration_audit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-memory"></i> Memory Configuration</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>Max server memory</strong> is set correctly (SQL Server should NOT consume all OS memory)</div>
        <div class="item-script"><i class="fas fa-file-code"></i> EXEC sp_configure 'max server memory';</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> <span class="tag tag-r">Common Mistake: Unlimited</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify no OS paging, slow queries, or application timeouts from memory pressure</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/memory_diagnostics.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-divide"></i> Parallelism Configuration</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>MAXDOP</strong> is set based on CPU count, NUMA, and workload type</div>
        <div class="item-script"><i class="fas fa-file-code"></i> EXEC sp_configure 'max degree of parallelism';</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text"><strong>Cost Threshold for Parallelism</strong> reviewed (default of 5 is often too low)</div>
        <div class="item-script"><i class="fas fa-file-code"></i> EXEC sp_configure 'cost threshold for parallelism';</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-compact-disc"></i> TempDB Configuration</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cfg06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">TempDB has multiple data files, equal size, equal growth, on fast storage</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/tempdb_configuration.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> <span class="tag tag-y">Check: PAGELATCH contention</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 05: DAILY HEALTH CHECKS ==================== -->
<div class="section-page" id="page-sec05">
  <div class="page-header">
    <h2>05. Daily Health Checks</h2>
    <p>Morning production health check routine for SQL Server environments.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-sun"></i> Morning Health Check</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run comprehensive health check stored procedure</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_HealthCheck.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only | Frequency: Daily</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Service is running</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Agent is running</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Disk space is adequate</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/disk_latency.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">CPU usage is within normal range</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/cpu_utilization.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Memory pressure check</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/memory_diagnostics.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check for failed SQL Agent jobs</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 09_Maintenance/failed_jobs.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh08" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check for suspect/offline databases</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT name, state_desc FROM sys.databases;</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh09" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Agent job monitor</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 08_Advanced/sql_agent_job_monitor.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clock"></i> Backup Validation</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh10" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review backup history</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_BackupReview.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh11" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify backup chain integrity</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_log_chain.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh12" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify backup file integrity</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_verification.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dh13" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify: Full backup, Differential, Log backup, Restore test</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clock"></i> DBA Daily Operational Workflow</h3>
    <p style="margin-bottom:12px;font-size:13px;color:var(--text-secondary);">Time-based workflow for structured DBA operations across different cadences.</p>
    <div class="time-workflow">
      <div class="time-slot">
        <div class="time-badge time-morning">8:00 AM<br><small>Morning</small></div>
        <div class="time-content">
          <h4>Morning Health Check</h4>
          <ul>
            <li>Backup validation - Full, Differential, Log</li>
            <li>Disk space review - All drives</li>
            <li>Failed SQL Agent jobs</li>
            <li>Error log review - Last 24 hours</li>
            <li>Blocking sessions - Current state</li>
            <li>AG/Replication health</li>
            <li>Service status - SQL Server + Agent</li>
          </ul>
        </div>
      </div>
      <div class="time-slot">
        <div class="time-badge time-daytime">During Day<br><small>Monitor</small></div>
        <div class="time-content">
          <h4>Continuous Monitoring</h4>
          <ul>
            <li>Blocking alerts - Respond immediately</li>
            <li>CPU spikes - Investigate source</li>
            <li>Deadlock tracking - Review patterns</li>
            <li>Storage alerts - Growth monitoring</li>
            <li>Long running queries - Identify outliers</li>
            <li>Application connection issues</li>
          </ul>
        </div>
      </div>
      <div class="time-slot">
        <div class="time-badge time-weekly">Weekly<br><small>Maintenance</small></div>
        <div class="time-content">
          <h4>Weekly Review Tasks</h4>
          <ul>
            <li>Index fragmentation review</li>
            <li>Statistics freshness check</li>
            <li>Database growth analysis</li>
            <li>Security review - New logins, permission changes</li>
            <li>Performance baseline comparison</li>
            <li>Capacity trending</li>
          </ul>
        </div>
      </div>
      <div class="time-slot">
        <div class="time-badge time-monthly">Monthly<br><small>Strategic</small></div>
        <div class="time-content">
          <h4>Monthly Strategic Tasks</h4>
          <ul>
            <li>Capacity planning review</li>
            <li>CU/Security patch review</li>
            <li>DR validation and failover test</li>
            <li>Backup restore test</li>
            <li>Security audit - Full scope</li>
            <li>Configuration drift check</li>
            <li>License compliance review</li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 06: MONITORING ==================== -->
<div class="section-page" id="page-sec06">
  <div class="page-header">
    <h2>06. Monitoring Checklist</h2>
    <p>Continuous monitoring setup and validation for proactive DBA operations.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-desktop"></i> Active Monitoring</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Active sessions monitoring is configured</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_ActiveSessions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Extended Events sessions are running</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 12_Extended_Events/active_xe_sessions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Query Store is enabled and healthy</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 08_Advanced/query_store_health.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Performance baselines are captured</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 14_Baselines/performance_snapshot.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Baseline capture procedure is set up</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_BaselineCapture.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Error log monitoring is configured</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 08_Advanced/error_log_and_connectivity.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Alert management is configured</div>
        <div class="item-script"><i class="fas fa-file-code"></i> preventive_measures/08_Alert_Management.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="mon08" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Dashboard views are operational</div>
        <div class="item-script"><i class="fas fa-file-code"></i> preventive_measures/09_Dashboard_Views.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 07: INCIDENT RESPONSE ==================== -->
<div class="section-page" id="page-sec07">
  <div class="page-header">
    <h2>07. Incident Response Playbook</h2>
    <p>Structured response procedures for production incidents.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-bolt"></i> Incident Response Flow</h3>
    <div class="flow-steps">
      <div class="flow-step"><i class="fas fa-bell"></i> Alert Received / Issue Reported</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-clipboard-check"></i> Collect Evidence (DMV snapshots, wait stats)</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-crosshairs"></i> Identify the Bottleneck Layer (5-Layer Model)</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-search"></i> Root Cause Investigation</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-wrench"></i> Apply Fix</div>
      <div class="flow-arrow"></div>
      <div class="flow-step"><i class="fas fa-file-alt"></i> Document RCA &amp; Prevent Recurrence</div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-exclamation-triangle"></i> Incident Priority Model (P1-P4)</h3>
    <p style="margin-bottom:12px;font-size:13px;color:var(--text-secondary);">Every incident must be classified. Classification drives response time and escalation path.</p>
    <table class="data-table">
      <thead><tr><th>Severity</th><th>Meaning</th><th>Response Time</th><th>Escalation</th><th>Example</th></tr></thead>
      <tbody>
        <tr><td><span class="severity-badge severity-p1">P1 - Critical</span></td><td>Database unavailable / Data loss risk</td><td><strong>Immediate</strong></td><td>DBA + App + Infra + Management</td><td>Instance down, AG failover, corruption</td></tr>
        <tr><td><span class="severity-badge severity-p2">P2 - High</span></td><td>Major degradation / Service impacted</td><td><strong>&lt; 30 min</strong></td><td>DBA + App team</td><td>Severe blocking, CPU 100%, log full</td></tr>
        <tr><td><span class="severity-badge severity-p3">P3 - Medium</span></td><td>Performance issue / Degraded experience</td><td><strong>Planned window</strong></td><td>DBA team</td><td>Slow queries, index fragmentation, growth</td></tr>
        <tr><td><span class="severity-badge severity-p4">P4 - Low</span></td><td>Improvement / Optimization</td><td><strong>Backlog</strong></td><td>DBA team</td><td>Config tuning, stats update, cleanup</td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-project-diagram"></i> Troubleshooting Decision Tree</h3>
    <p style="margin-bottom:8px;font-size:13px;color:var(--text-secondary);">Interactive diagnostic flow. Scroll horizontally/vertically to navigate. Start at the top and follow the Yes/No path.</p>
    <div class="dt-legend">
      <span><span class="dt-legend-dot" style="background:var(--accent);"></span> Decision</span>
      <span><span class="dt-legend-dot" style="background:var(--success);"></span> Action</span>
      <span><span class="dt-legend-dot" style="background:var(--warning);"></span> Script</span>
      <span><span class="dt-legend-dot" style="background:rgba(239,68,68,0.3);"></span> No Path</span>
      <span><span class="dt-legend-dot" style="background:rgba(34,197,94,0.3);"></span> Yes Path</span>
    </div>
    <div class="decision-tree-wrapper">
      <div class="decision-tree">
        <div class="dt-level">
          <div class="dt-node question" style="font-size:15px;border-color:var(--danger);width:280px;">Application is Slow / Down</div>
          <div class="dt-connector"></div>
          <div class="dt-node question">Can you connect to SQL Server?</div>
          <div class="dt-connector"></div>
        </div>
        <div class="dt-branch">
          <div class="dt-arm">
            <div class="dt-branch-label dt-no">NO</div>
            <div class="dt-connector"></div>
            <div class="dt-node action">Check SQL Service status<br>Check Memory / OS</div>
            <div class="dt-connector"></div>
            <div class="dt-node script">01_Server_OS/memory_diagnostics.sql</div>
          </div>
          <div class="dt-arm">
            <div class="dt-branch-label dt-yes">YES</div>
            <div class="dt-connector"></div>
            <div class="dt-node question">Is blocking present?</div>
            <div class="dt-connector"></div>
          </div>
        </div>
        <div style="display:flex;justify-content:center;width:100%;margin-top:4px;">
          <div class="dt-arm" style="max-width:900px;">
            <div class="dt-branch">
              <div class="dt-arm">
                <div class="dt-branch-label dt-yes">YES</div>
                <div class="dt-connector"></div>
                <div class="dt-node action">Analyze blocker chain<br>Check transaction age</div>
                <div class="dt-connector"></div>
                <div class="dt-node script">04_Performance_Diagnostics/blocking_and_deadlocks.sql</div>
              </div>
              <div class="dt-arm">
                <div class="dt-branch-label dt-no">NO</div>
                <div class="dt-connector"></div>
                <div class="dt-node question">Is CPU &gt; 90%?</div>
                <div class="dt-connector"></div>
              </div>
            </div>
          </div>
        </div>
        <div style="display:flex;justify-content:center;width:100%;margin-top:4px;">
          <div class="dt-arm" style="max-width:900px;">
            <div class="dt-branch">
              <div class="dt-arm">
                <div class="dt-branch-label dt-yes">YES</div>
                <div class="dt-connector"></div>
                <div class="dt-node script">04_Performance_Diagnostics/top_resource_queries.sql</div>
              </div>
              <div class="dt-arm">
                <div class="dt-branch-label dt-no">NO</div>
                <div class="dt-connector"></div>
                <div class="dt-node action">Check wait statistics</div>
                <div class="dt-connector"></div>
                <div class="dt-node script">00_Framework/sp_DBA_WaitAnalysis.sql</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clipboard-check"></i> Production Execution Checklist</h3>
    <p style="margin-bottom:8px;font-size:13px;color:var(--text-secondary);">Before running any script, verify these items. Check each box to confirm:</p>
    <div class="safety-panel-enhanced">
      <h4><i class="fas fa-exclamation-triangle"></i> Before You Execute</h4>
      <div class="safety-checklist-enhanced">
        <label class="safety-check-item-enhanced"><input type="checkbox"> Correct server instance verified</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Correct database context verified</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Change ticket available (if required)</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Read vs write impact confirmed</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Baseline captured before changes</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Output captured / screenshot taken</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Incident ID recorded</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Rollback plan exists</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Application team notified if needed</label>
        <label class="safety-check-item-enhanced"><input type="checkbox"> Evidence attached to incident ticket</label>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-camera"></i> Evidence Collection Module</h3>
    <p style="margin-bottom:8px;font-size:13px;color:var(--text-secondary);">Collect this data BEFORE making any changes. Use the Incident Snapshot to export all evidence at once.</p>
    <div class="evidence-card">
      <h4><i class="fas fa-clipboard-list"></i> Incident Snapshot Checklist</h4>
      <div class="evidence-grid">
        <div class="evidence-item"><label>Incident ID</label> <input type="text" class="notes-field" placeholder="e.g. INC-2026-0622" style="flex:1;"></div>
        <div class="evidence-item"><label>Timestamp</label> <input type="text" class="notes-field" id="evidenceTimestamp" placeholder="" style="flex:1;" readonly></div>
        <div class="evidence-item"><label>Environment</label>
          <select class="notes-field" style="flex:1;"><option>Production</option><option>UAT</option><option>Development</option><option>DR</option></select>
        </div>
        <div class="evidence-item"><label>Server</label> <input type="text" class="notes-field" placeholder="Server name" style="flex:1;"></div>
        <div class="evidence-item"><label>Database</label> <input type="text" class="notes-field" placeholder="Affected database" style="flex:1;"></div>
        <div class="evidence-item"><label>Application</label> <input type="text" class="notes-field" placeholder="App name" style="flex:1;"></div>
        <div class="evidence-item"><label>Reported By</label> <input type="text" class="notes-field" placeholder="Who reported" style="flex:1;"></div>
        <div class="evidence-item"><label>Error Message</label> <input type="text" class="notes-field" placeholder="Key error text" style="flex:1;"></div>
        <div class="evidence-item"><label>Severity</label>
          <select class="notes-field" style="flex:1;"><option>P1 - Critical</option><option>P2 - High</option><option>P3 - Medium</option><option selected>P4 - Low</option></select>
        </div>
        <div class="evidence-item"><label>Business Impact</label> <input type="text" class="notes-field" placeholder="e.g. Order processing halted" style="flex:1;"></div>
      </div>
      <div style="margin-top:12px;">
        <div style="font-size:12px;color:var(--text-secondary);margin-bottom:6px;font-weight:600;">Collected Evidence:</div>
        <div class="evidence-checkbox-grid">
          <label class="evidence-check-item"><input type="checkbox"> Blocking Chain</label>
          <label class="evidence-check-item"><input type="checkbox"> Wait Stats Snapshot</label>
          <label class="evidence-check-item"><input type="checkbox"> CPU Metrics</label>
          <label class="evidence-check-item"><input type="checkbox"> Memory Metrics</label>
          <label class="evidence-check-item"><input type="checkbox"> Disk I/O Metrics</label>
          <label class="evidence-check-item"><input type="checkbox"> Query Execution Plan</label>
          <label class="evidence-check-item"><input type="checkbox"> Error Log Entries</label>
          <label class="evidence-check-item"><input type="checkbox"> Recent Deployment Check</label>
        </div>
      </div>
      <div style="margin-top:10px;">
        <button class="btn-accent" onclick="collectEvidence()"><i class="fas fa-download"></i> Export Incident Snapshot</button>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-check-double"></i> Incident Response Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Capture initial evidence before any action</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run health check to establish baseline</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_HealthCheck.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check active sessions and blocking</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_ActiveSessions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze wait statistics</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_WaitAnalysis.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Identify top resource-consuming queries</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/top_resource_queries.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check for recent changes (deployments, config changes)</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ir07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Apply appropriate fix and document RCA</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 08: PERFORMANCE TUNING ==================== -->
<div class="section-page" id="page-sec08">
  <div class="page-header">
    <h2>08. Performance Troubleshooting</h2>
    <p>Systematic approach to identifying and resolving SQL Server performance issues.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clipboard-list"></i> Before Tuning Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Collect: Query text, Execution plan, Wait stats, IO stats, CPU stats</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> <span class="tag tag-r">Never tune based only on "query is slow"</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-tachometer-alt"></i> CPU Issues</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze CPU utilization history</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/cpu_utilization.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Find top resource-consuming queries</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/top_resource_queries.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Deep plan cache analysis</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_PlanCacheAnalyzer.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Plan cache deep dive</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/plan_cache_deep_dive.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-hdd"></i> IO &amp; Disk Bottlenecks</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check disk latency</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/disk_latency.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check database file growth patterns</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/database_files_growth.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt08" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check VLF fragmentation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/vlf_fragmentation.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-wave-square"></i> Wait Statistics</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt09" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze wait statistics to identify bottleneck</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_WaitAnalysis.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt10" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review wait statistics reference</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/wait_statistics.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-sitemap"></i> Index &amp; Statistics</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt11" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review index usage and fragmentation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_IndexReview.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt12" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Advanced index analysis</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 05_Index_Statistics/advanced_index_analysis.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt13" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Index usage efficiency</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 05_Index_Statistics/index_usage_efficiency.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt14" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Physical stats and heap analysis</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 05_Index_Statistics/physical_stats_and_heaps.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt15" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Statistics freshness check</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 05_Index_Statistics/statistics_freshness.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pt16" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Query Store regressions</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_QueryStoreRegressions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 09: BLOCKING & DEADLOCKS ==================== -->
<div class="section-page" id="page-sec09">
  <div class="page-header">
    <h2>09. Blocking &amp; Deadlocks</h2>
    <p>Production checklist for identifying and resolving blocking and deadlock issues.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-hand-rock"></i> Blocking Troubleshooting</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="bd01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check active sessions and blocking chains</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_ActiveSessions.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="bd02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Analyze blocking and deadlock patterns</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/blocking_and_deadlocks.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="bd03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Deep deadlock analysis with XML deadlock graphs</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/deadlock_analysis.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-search"></i> Root Cause Investigation</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="bd04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Identify root blocker and transaction age</div>
        <div class="item-script"><i class="fas fa-file-code"></i> DBCC OPENTRAN;</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="bd05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review: Kill session? Application fix? Index improvement? Transaction redesign?</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 10: TRANSACTION LOG ==================== -->
<div class="section-page" id="page-sec10">
  <div class="page-header">
    <h2>10. Transaction Log Issues</h2>
    <p>Handling "transaction log full" errors and log management.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-scroll"></i> Transaction Log Full Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="tl01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check recovery model</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT name, recovery_model_desc FROM sys.databases;</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="tl02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Find log reuse wait reason</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT name, log_reuse_wait_desc FROM sys.databases;</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="tl03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check VLF fragmentation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/vlf_fragmentation.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="tl04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify backup chain is intact (no broken log chain)</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_log_chain.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-list-ul"></i> Common Causes</h3>
    <table class="data-table">
      <thead><tr><th>Cause</th><th>Diagnosis</th><th>Resolution</th></tr></thead>
      <tbody>
        <tr><td>Missing log backup</td><td>Check backup schedule</td><td>Enable log backups</td></tr>
        <tr><td>Long running transaction</td><td>DBCC OPENTRAN</td><td>Kill or fix transaction</td></tr>
        <tr><td>Replication delay</td><td>Check replication status</td><td>Fix distribution agent</td></tr>
        <tr><td>AG sync issue</td><td>Check AG dashboard</td><td>Resolve sync blocker</td></tr>
      </tbody>
    </table>
  </div>
</div>

<!-- ==================== SEC 11: BACKUP & RECOVERY ==================== -->
<div class="section-page" id="page-sec11">
  <div class="page-header">
    <h2>11. Backup &amp; Recovery</h2>
    <p>Backup strategy validation and disaster recovery readiness.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-shield-alt"></i> RPO &amp; RTO Definitions</h3>
    <table class="data-table">
      <thead><tr><th>Term</th><th>Definition</th><th>Question</th></tr></thead>
      <tbody>
        <tr><td><strong>RPO</strong></td><td>Recovery Point Objective</td><td>How much data loss is acceptable?</td></tr>
        <tr><td><strong>RTO</strong></td><td>Recovery Time Objective</td><td>How quickly must recovery happen?</td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clipboard-check"></i> Backup Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="br01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review backup history</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_BackupReview.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify backup chain integrity</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_log_chain.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Verify backup file integrity (RESTORE VERIFYONLY)</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_verification.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Restore test simulation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/restore_test_simulator.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Backup tested and restore verified</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br06" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">DR procedure documented</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="br07" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Failover tested</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 12: SECURITY AUDIT ==================== -->
<div class="section-page" id="page-sec12">
  <div class="page-header">
    <h2>12. Security Audit</h2>
    <p>SQL Server security review and compliance checklist.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-user-shield"></i> Security Audit Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run comprehensive security audit</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_SecurityAudit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Login audit</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 07_Security/login_audit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Authorization audit</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 07_Security/authorization_audit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Encryption hardening review</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 07_Security/encryption_hardening.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-list-check"></i> Security Review Items</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa05" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Excess sysadmin users identified and reduced</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Disabled accounts cleaned up</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Shared/generic accounts eliminated</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="sa08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">SA account review completed</div></div>
    </div>
  </div>
</div>

<!-- ==================== SEC 13: HIGH AVAILABILITY ==================== -->
<div class="section-page" id="page-sec13">
  <div class="page-header">
    <h2>13. High Availability</h2>
    <p>AlwaysOn AG, Failover, and Replication health checks.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-network-wired"></i> High Availability Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="ha01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Monitor AlwaysOn AG health</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/alwayson_ag_monitor.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ha02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Failover readiness validated</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ha03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Replication health check</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 08_Advanced/replication_monitor.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="ha04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Log shipping / backup chain validation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_log_chain.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 14: DISASTER RECOVERY ==================== -->
<div class="section-page" id="page-sec14">
  <div class="page-header">
    <h2>14. Disaster Recovery</h2>
    <p>DR planning, testing, and validation procedures.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-life-ring"></i> DR Readiness Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="dr01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">RPO/RTO requirements documented per database</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dr02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Restore test simulation completed</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/restore_test_simulator.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dr03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">DR runbook documented and tested</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dr04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Failover tested with documented results</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dr05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Backup verification completed</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/backup_verification.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 15: CAPACITY PLANNING ==================== -->
<div class="section-page" id="page-sec15">
  <div class="page-header">
    <h2>15. Capacity Planning</h2>
    <p>Proactive capacity monitoring and growth forecasting.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-chart-line"></i> Capacity Planning Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cp01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Database growth forecast</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 10_Capacity_Planning/database_growth_forecast.sql</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cp02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Database file growth analysis</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/database_files_growth.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span> Risk: Read Only</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cp03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Performance snapshot baseline</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 14_Baselines/performance_snapshot.sql</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cp04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Questions: Data growth expected? Index growth? Log growth? Purging strategy?</div>
        <div class="item-meta"><span class="priority-badge priority-medium">Medium</span></div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 16: CHANGE MANAGEMENT ==================== -->
<div class="section-page" id="page-sec16">
  <div class="page-header">
    <h2>16. Change Management</h2>
    <p>Pre-production change validation checklist.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-exchange-alt"></i> Change Request Checklist</h3>
    <div class="change-checklist-grid">
      <div class="change-checklist-col">
        <h4 style="color:var(--accent);"><i class="fas fa-arrow-left"></i> Before Change</h4>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm01" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Expected downtime documented</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm02" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Rollback plan documented and tested</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm03" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Full backup completed before change</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm04" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Testing completed in non-production</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm05" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Approval received from stakeholders</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm06" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Impact assessment completed</div></div>
        </div>
      </div>
      <div class="change-checklist-col">
        <h4 style="color:var(--success);"><i class="fas fa-arrow-right"></i> After Change</h4>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm07" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Validation completed successfully</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm08" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Monitoring enabled and alerts active</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm09" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Documentation updated</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm10" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Application connectivity verified</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm11" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Performance baseline compared</div></div>
        </div>
        <div class="checklist-item">
          <input type="checkbox" data-id="cm12" onchange="saveCheck(this)">
          <div class="item-content"><div class="item-text">Change ticket closed with results</div></div>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 17: AUTOMATION ==================== -->
<div class="section-page" id="page-sec17">
  <div class="page-header">
    <h2>17. Automation Scripts</h2>
    <p>DBA automation framework and utility scripts.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-robot"></i> Automation Maturity Roadmap</h3>
    <p style="margin-bottom:8px;font-size:13px;color:var(--text-secondary);">Track your automation journey from manual processes to self-healing infrastructure.</p>
    <div class="automation-level">
      <div class="auto-level-card" style="border-color:var(--text-secondary);">
        <div class="level-num">1</div>
        <div class="level-name">Manual Checklist</div>
        <div class="level-desc">DBA manually runs scripts. All actions are human-initiated.</div>
        <div style="margin-top:8px;"><span class="tag tag-b">Starting point</span></div>
      </div>
      <div class="auto-level-card" style="border-color:var(--accent);">
        <div class="level-num">2</div>
        <div class="level-name">Scheduled Reports</div>
        <div class="level-desc">Health checks run on schedule via SQL Agent.</div>
        <div style="margin-top:8px;"><span class="tag tag-b">SQL Agent Jobs</span></div>
      </div>
      <div class="auto-level-card" style="border-color:var(--warning);">
        <div class="level-num">3</div>
        <div class="level-name">Alert-Driven</div>
        <div class="level-desc">Threshold-based alerts trigger investigation proactively.</div>
        <div style="margin-top:8px;"><span class="tag tag-y">Alerts + Dashboards</span></div>
      </div>
      <div class="auto-level-card" style="border-color:var(--success);">
        <div class="level-num">4</div>
        <div class="level-name">Self-Healing</div>
        <div class="level-desc">Automated remediation for known patterns.</div>
        <div style="margin-top:8px;"><span class="tag tag-g">Autonomous Ops</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-robot"></i> Framework Deployment</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="au01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Deploy DBA Framework (all stored procedures and functions)</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/00_Deploy_Framework.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span> <span class="tag tag-y">Run FIRST</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="au02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Deploy via PowerShell automation</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/00_Deploy_Framework.ps1</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="au03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">DBA Repository database created</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Repository/DBARepository_Create.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-cogs"></i> Utility Procedures</h3>
    <table class="data-table">
      <thead><tr><th>Procedure</th><th>Purpose</th><th>Path</th></tr></thead>
      <tbody>
        <tr><td><code>sp_DBA_ActiveSessions</code></td><td>Real-time active session monitor</td><td class="script-path">00_Framework/sp_DBA_ActiveSessions.sql</td></tr>
        <tr><td><code>sp_DBA_ForEachDatabase</code></td><td>Run command against all databases</td><td class="script-path">00_Framework/sp_DBA_ForEachDatabase.sql</td></tr>
        <tr><td><code>sp_DBA_SaveAssessmentRun</code></td><td>Persist health check results</td><td class="script-path">00_Framework/sp_DBA_SaveAssessmentRun.sql</td></tr>
        <tr><td><code>fn_DBA_ExcludedWaitTypes</code></td><td>Filter wait types</td><td class="script-path">00_Framework/fn_DBA_ExcludedWaitTypes.sql</td></tr>
        <tr><td><code>fn_DBA_AgentRunDurationSeconds</code></td><td>Calculate job duration</td><td class="script-path">00_Framework/fn_DBA_AgentRunDurationSeconds.sql</td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-shield-alt"></i> Preventive Measures</h3>
    <table class="data-table">
      <thead><tr><th>Script</th><th>Purpose</th><th>Path</th></tr></thead>
      <tbody>
        <tr><td>Governance DB Setup</td><td>Create governance database</td><td class="script-path">preventive_measures/01_Create_Governance_Database.sql</td></tr>
        <tr><td>Running Query Capture</td><td>Capture running queries</td><td class="script-path">preventive_measures/02_Capture_Running_Queries.sql</td></tr>
        <tr><td>Long Running Queries</td><td>Monitor long queries</td><td class="script-path">preventive_measures/03_Check_Long_Running_Queries.sql</td></tr>
        <tr><td>Massive DML</td><td>Check massive DML operations</td><td class="script-path">preventive_measures/04_Check_Massive_DML.sql</td></tr>
        <tr><td>Blocked Apps</td><td>Check blocked applications</td><td class="script-path">preventive_measures/05_Check_Blocked_Applications.sql</td></tr>
        <tr><td>Query Policy</td><td>Enforce query policies</td><td class="script-path">preventive_measures/06_Enforce_Query_Policy.sql</td></tr>
        <tr><td>Extended Events</td><td>Setup Extended Events</td><td class="script-path">preventive_measures/07_Setup_Extended_Events.sql</td></tr>
        <tr><td>Alert Management</td><td>Configure alerts</td><td class="script-path">preventive_measures/08_Alert_Management.sql</td></tr>
        <tr><td>Dashboard Views</td><td>Create monitoring views</td><td class="script-path">preventive_measures/09_Dashboard_Views.sql</td></tr>
        <tr><td>Agent Jobs</td><td>Create SQL Agent jobs</td><td class="script-path">preventive_measures/10_Create_SQL_Agent_Jobs.sql</td></tr>
        <tr><td>Resource Governor</td><td>Setup Resource Governor</td><td class="script-path">preventive_measures/11_Setup_Resource_Governor.sql</td></tr>
      </tbody>
    </table>
  </div>
</div>

<!-- ==================== SEC 18: CASE STUDIES ==================== -->
<div class="section-page" id="page-sec18">
  <div class="page-header">
    <h2>18. DBA Case Studies</h2>
    <p>Real-world production scenarios with resolution approaches.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-exclamation-circle"></i> Scenario 1: "Application is slow"</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs01" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check CPU pressure</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 01_Server_OS/cpu_utilization.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs02" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check blocking</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/blocking_and_deadlocks.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs03" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check expensive queries</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/top_resource_queries.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs04" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Review wait statistics</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_WaitAnalysis.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs05" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Validate execution plan</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_PlanCacheAnalyzer.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check recent changes and apply fix</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-layer-group"></i> Scenario 2: Blocking Storm</h3>
    <p style="font-size:13px;color:var(--text-secondary);margin-bottom:8px;">Symptoms: Users cannot save, Queries hanging</p>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Find root blocker using sp_who2 active</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check transaction age with DBCC OPENTRAN</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs09" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Resolution: Kill session / Application fix / Index improvement / Transaction redesign</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-database"></i> Scenario 3: Transaction Log Full</h3>
    <p style="font-size:13px;color:var(--text-secondary);margin-bottom:8px;">Error: "The transaction log for database is full"</p>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs10" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Check recovery model and log reuse wait</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/vlf_fragmentation.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs11" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Common causes: Missing log backup / Long running tx / Replication delay / AG sync issue</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-microchip"></i> Scenario 4: SQL Server CPU 100%</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs12" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Find top 20 expensive queries</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 04_Performance_Diagnostics/top_resource_queries.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs13" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Investigate: Bad plan / Parameter sniffing / Missing index / Data growth</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-expand-arrows-alt"></i> Scenario 5: Database Growth Problem</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs14" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Find largest tables with sp_spaceused</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 03_Storage_Engine/database_files_growth.sql</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="cs15" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Questions: Data growth expected? Index growth? Log growth? Purging strategy?</div></div>
    </div>
  </div>
</div>

<!-- ==================== SEC 19: RCA TEMPLATES ==================== -->
<div class="section-page" id="page-sec19">
  <div class="page-header">
    <h2>19. RCA Templates</h2>
    <p>Root Cause Analysis documentation template for post-incident review.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clipboard-list"></i> Incident Summary</h3>
    <table class="data-table">
      <thead><tr><th>Field</th><th>Details</th></tr></thead>
      <tbody>
        <tr><td>Incident Date/Time</td><td style="width:70%"></td></tr>
        <tr><td>Duration</td><td></td></tr>
        <tr><td>Severity</td><td></td></tr>
        <tr><td>Affected Systems</td><td></td></tr>
        <tr><td>Impact</td><td></td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-search"></i> Root Cause Analysis</h3>
    <table class="data-table">
      <thead><tr><th>Field</th><th>Details</th></tr></thead>
      <tbody>
        <tr><td>Root Cause</td><td style="width:70%"></td></tr>
        <tr><td>Contributing Factors</td><td></td></tr>
        <tr><td>Detection Method</td><td></td></tr>
        <tr><td>Time to Detect</td><td></td></tr>
        <tr><td>Time to Resolve</td><td></td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-wrench"></i> Resolution &amp; Prevention</h3>
    <table class="data-table">
      <thead><tr><th>Field</th><th>Details</th></tr></thead>
      <tbody>
        <tr><td>Immediate Fix</td><td style="width:70%"></td></tr>
        <tr><td>Permanent Fix</td><td></td></tr>
        <tr><td>Prevention Measures</td><td></td></tr>
        <tr><td>Monitoring Improvements</td><td></td></tr>
        <tr><td>Lessons Learned</td><td></td></tr>
      </tbody>
    </table>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-book"></i> Reference Scripts for Investigation</h3>
    <table class="data-table">
      <thead><tr><th>Investigation Area</th><th>Script</th></tr></thead>
      <tbody>
        <tr><td>Health Check</td><td class="script-path">00_Framework/sp_DBA_HealthCheck.sql</td></tr>
        <tr><td>Wait Analysis</td><td class="script-path">00_Framework/sp_DBA_WaitAnalysis.sql</td></tr>
        <tr><td>Blocking Analysis</td><td class="script-path">04_Performance_Diagnostics/blocking_and_deadlocks.sql</td></tr>
        <tr><td>Deadlock Analysis</td><td class="script-path">04_Performance_Diagnostics/deadlock_analysis.sql</td></tr>
        <tr><td>Top Resource Queries</td><td class="script-path">04_Performance_Diagnostics/top_resource_queries.sql</td></tr>
        <tr><td>Plan Cache</td><td class="script-path">00_Framework/sp_DBA_PlanCacheAnalyzer.sql</td></tr>
        <tr><td>CPU Analysis</td><td class="script-path">01_Server_OS/cpu_utilization.sql</td></tr>
        <tr><td>Memory Diagnostics</td><td class="script-path">01_Server_OS/memory_diagnostics.sql</td></tr>
        <tr><td>Disk Latency</td><td class="script-path">01_Server_OS/disk_latency.sql</td></tr>
      </tbody>
    </table>
  </div>
</div>

<!-- ==================== SEC 20: DBA GROWTH PATH ==================== -->
<div class="section-page" id="page-sec20">
  <div class="page-header">
    <h2>20. DBA Growth Path</h2>
    <p>Career development checklist from Junior DBA to Senior DBA.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-seedling"></i> Junior DBA / 0-2 Years</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp01" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Understand SQL Server architecture (storage engine, query processor, memory manager)</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp02" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Master backup and restore operations</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp03" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Understand DMVs and basic performance monitoring</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp04" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Learn to read execution plans</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp05" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Understand SQL Server Agent jobs and maintenance plans</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-user-tie"></i> Mid-Level DBA / 2-5 Years</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Master performance tuning and query optimization</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Understand AlwaysOn, Failover Clustering, Log Shipping</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Implement monitoring and alerting frameworks</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp09" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Master security auditing and compliance</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp10" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Develop automation scripts (PowerShell, T-SQL)</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-crown"></i> Senior DBA / 5+ Years</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp11" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Capacity planning and architecture design</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp12" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Disaster recovery planning and testing</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp13" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Change management process ownership</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp14" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Mentoring junior DBAs and knowledge transfer</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="gp15" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Cloud migration and hybrid architecture</div></div>
    </div>
  </div>
</div>

<!-- ==================== SEC 21: PATCH MANAGEMENT ==================== -->
<div class="section-page" id="page-sec21">
  <div class="page-header">
    <h2>21. SQL Server Patch Management</h2>
    <p>CU and security patch lifecycle management for SQL Server environments.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-wrench"></i> Patch Assessment</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Current CU level documented</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT @@VERSION;</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check for latest available CU from Microsoft</div>
        <div class="item-meta"><span class="priority-badge priority-high">High</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review security patches / CVEs for current version</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm04" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Compatibility validation completed in non-production</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 02_Instance_Config/database_compatibility_audit.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm05" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Application regression testing completed</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-clipboard-check"></i> Patch Application Checklist</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Full backup completed before patching</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Change ticket approved</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Maintenance window confirmed</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm09" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Application team notified</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm10" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Rollback plan documented</div></div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-check-circle"></i> Post-Patch Validation</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm11" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">SQL Server version verified post-patch</div>
        <div class="item-script"><i class="fas fa-file-code"></i> SELECT @@VERSION;</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm12" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">All services running (SQL + Agent)</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm13" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Application connectivity verified</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm14" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Run health check post-patch</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 00_Framework/sp_DBA_HealthCheck.sql</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm15" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">AG/HA health validated</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 06_HA_DR/alwayson_ag_monitor.sql</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="pm16" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Performance baseline comparison</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 14_Baselines/performance_snapshot.sql</div>
      </div>
    </div>
  </div>
</div>

<!-- ==================== SEC 22: DATA CORRUPTION ==================== -->
<div class="section-page" id="page-sec22">
  <div class="page-header">
    <h2>22. Data Corruption Response</h2>
    <p>Handling database corruption: detection, assessment, and recovery procedures.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-exclamation-triangle"></i> Corruption Detection</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc01" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Run DBCC CHECKDB on affected database</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 09_Maintenance/last_checkdb_dates.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc02" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Check SQL Server error log for 823/824/825 errors</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 08_Advanced/error_log_and_connectivity.sql</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc03" onchange="saveCheck(this)">
      <div class="item-content">
        <div class="item-text">Review Windows Event Log for I/O errors</div>
        <div class="item-meta"><span class="priority-badge priority-critical">Critical</span></div>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-search"></i> Corruption Assessment</h3>
    <div class="corruption-step">
      <div class="corruption-num">1</div>
      <div>
        <strong>Identify Scope</strong>
        <p style="font-size:13px;color:var(--text-secondary);">Which database? Which objects? How many pages affected? Is it clustered vs nonclustered index vs heap?</p>
      </div>
    </div>
    <div class="corruption-step">
      <div class="corruption-num">2</div>
      <div>
        <strong>Check Backup Chain</strong>
        <p style="font-size:13px;color:var(--text-secondary);">Verify last known good backup. Check if log backups are available for point-in-time recovery.</p>
        <div class="item-script" style="display:inline-flex;margin-top:4px;"><i class="fas fa-file-code"></i> 06_HA_DR/backup_log_chain.sql</div>
      </div>
    </div>
    <div class="corruption-step">
      <div class="corruption-num">3</div>
      <div>
        <strong>Assess Recovery Options</strong>
        <p style="font-size:13px;color:var(--text-secondary);">Can you restore from backup? Is page-level restore possible? Is emergency mode repair the last resort?</p>
      </div>
    </div>
    <div class="corruption-step">
      <div class="corruption-num">4</div>
      <div>
        <strong>Decision Point</strong>
        <p style="font-size:13px;color:var(--text-secondary);"><strong>Preferred:</strong> Restore from backup. <strong>Alternative:</strong> Page-level restore. <strong>Last resort:</strong> DBCC CHECKDB with REPAIR_ALLOW_DATA_LOSS (requires Microsoft support).</p>
      </div>
    </div>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-life-ring"></i> Recovery Procedures</h3>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc04" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Restore from most recent clean backup</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc05" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Apply log backups for point-in-time recovery if possible</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc06" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">If page restore: identify specific corrupt pages and restore individually</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc07" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">If emergency mode repair needed: document approval from Microsoft Support</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc08" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Post-recovery: Run DBCC CHECKDB to verify integrity</div>
        <div class="item-script"><i class="fas fa-file-code"></i> 09_Maintenance/last_checkdb_dates.sql</div>
      </div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc09" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Investigate root cause: storage failure, power issue, driver bug, memory issue</div></div>
    </div>
    <div class="checklist-item">
      <input type="checkbox" data-id="dc10" onchange="saveCheck(this)">
      <div class="item-content"><div class="item-text">Increase DBCC CHECKDB frequency if corruption detected</div></div>
    </div>
  </div>
</div>

<!-- ==================== SEC 23: WAIT STATISTICS KNOWLEDGE BASE ==================== -->
<div class="section-page" id="page-sec23">
  <div class="page-header">
    <h2>23. Wait Statistics Knowledge Base</h2>
    <p>Senior DBA reference for interpreting wait types and determining corrective actions.</p>
  </div>
  <div class="card-box">
    <h3><i class="fas fa-search"></i> Wait Type Lookup</h3>
    <div style="margin-bottom:12px;">
      <input type="text" id="waitSearchInput" placeholder="Search wait types (e.g. WRITELOG, CXPACKET, PAGEIOLATCH)..." style="width:100%;padding:10px 14px;border:1px solid var(--border);border-radius:8px;background:var(--bg-hover);color:var(--text-primary);font-size:14px;" oninput="filterWaitTypes()">
    </div>
  </div>
  <div id="waitTypeCards">
    <div class="kb-card" data-wait="PAGEIOLATCH">
      <h4>PAGEIOLATCH</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting for physical I/O read/write to complete from disk</div>
      <div class="kb-field"><strong>Symptoms:</strong> Slow queries, high disk latency, timeouts</div>
      <div class="kb-field"><strong>Check:</strong> Disk latency, IO statistics, storage health</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">01_Server_OS/disk_latency.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Upgrade storage (SSD/NVMe), optimize queries to reduce I/O, review file placement</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-r">High impact</span></div>
    </div>
    <div class="kb-card" data-wait="CXPACKET">
      <h4>CXPACKET</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting for parallel query threads to synchronize</div>
      <div class="kb-field"><strong>Symptoms:</strong> High parallelism, skewed thread distribution, CXCONSUMER also high</div>
      <div class="kb-field"><strong>Check:</strong> MAXDOP setting, parallel execution plans, Cost Threshold</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">EXEC sp_configure 'max degree of parallelism';</span></div>
      <div class="kb-field"><strong>Fix:</strong> Adjust MAXDOP, increase Cost Threshold for Parallelism, fix skewed parallel plans</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Often benign if CXCONSUMER present</span></div>
    </div>
    <div class="kb-card" data-wait="CXCONSUMER">
      <h4>CXCONSUMER</h4>
      <div class="kb-field"><strong>Meaning:</strong> Consumer thread waiting for producer thread in parallel exchange</div>
      <div class="kb-field"><strong>Symptoms:</strong> Paired with CXPACKET; indicates consumer is slower than producer</div>
      <div class="kb-field"><strong>Check:</strong> Execution plans for parallelism skew</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">00_Framework/sp_DBA_PlanCacheAnalyzer.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Optimize the query causing skew; usually a query-level issue, not a config issue</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-g">Usually benign</span></div>
    </div>
    <div class="kb-card" data-wait="RESOURCE_SEMAPHORE">
      <h4>RESOURCE_SEMAPHORE</h4>
      <div class="kb-field"><strong>Meaning:</strong> Query waiting for memory grant to start execution</div>
      <div class="kb-field"><strong>Symptoms:</strong> Queries queued, memory pressure, query timeouts</div>
      <div class="kb-field"><strong>Check:</strong> Memory grants pending, available memory, large queries</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">01_Server_OS/memory_diagnostics.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Reduce memory-intensive queries, increase max server memory, fix parameter sniffing</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-r">High impact</span></div>
    </div>
    <div class="kb-card" data-wait="WRITELOG">
      <h4>WRITELOG</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting for transaction log write to complete</div>
      <div class="kb-field"><strong>Symptoms:</strong> Slow commits, high log file I/O, latency on log drive</div>
      <div class="kb-field"><strong>Check:</strong> Log file latency, VLF count, transaction activity</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">01_Server_OS/disk_latency.sql</span> | <span class="script-path">03_Storage_Engine/vlf_fragmentation.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Move log to faster storage, reduce large transactions, fix VLF fragmentation</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-r">High impact</span></div>
    </div>
    <div class="kb-card" data-wait="LCK_M">
      <h4>LCK_M_* (All Lock Waits)</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting to acquire a lock of specific type (S, X, U, IX, etc.)</div>
      <div class="kb-field"><strong>Symptoms:</strong> Blocking chains, timeouts, application delays</div>
      <div class="kb-field"><strong>Check:</strong> Blocking sessions, lock escalation, transaction isolation level</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">00_Framework/sp_DBA_ActiveSessions.sql</span> | <span class="script-path">04_Performance_Diagnostics/blocking_and_deadlocks.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Optimize blocking queries, add indexes, review isolation levels, consider lock escalation</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-r">High impact</span></div>
    </div>
    <div class="kb-card" data-wait="PAGELATCH_UP">
      <h4>PAGELATCH_UP / PAGELATCH_EX / PAGELATCH_SH</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting for in-memory latch on a data page (not disk I/O)</div>
      <div class="kb-field"><strong>Symptoms:</strong> High contention on specific pages, often TempDB allocation</div>
      <div class="kb-field"><strong>Check:</strong> Contention on alloc pages, TempDB page contention</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">03_Storage_Engine/tempdb_configuration.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Add TempDB files, enable TF-1118, optimize TempDB-heavy operations</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Medium impact</span></div>
    </div>
    <div class="kb-card" data-wait="SOS_SCHEDULER_YIELD">
      <h4>SOS_SCHEDULER_YIELD</h4>
      <div class="kb-field"><strong>Meaning:</strong> Task voluntarily yielded the scheduler, waiting to be rescheduled</div>
      <div class="kb-field"><strong>Symptoms:</strong> High when many CPU-bound queries, often with high CPU usage</div>
      <div class="kb-field"><strong>Check:</strong> CPU utilization, top CPU-consuming queries</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">01_Server_OS/cpu_utilization.sql</span> | <span class="script-path">04_Performance_Diagnostics/top_resource_queries.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Optimize CPU-heavy queries, reduce unnecessary compiles, review parallelism</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Medium impact - investigate when CPU is high</span></div>
    </div>
    <div class="kb-card" data-wait="LATCH_EX">
      <h4>LATCH_EX / LATCH_SH / LATCH_UP</h4>
      <div class="kb-field"><strong>Meaning:</strong> Waiting for a non-page latch (internal SQL Server structure protection)</div>
      <div class="kb-field"><strong>Symptoms:</strong> Metadata contention, tempdb contention, or buffer pool issues</div>
      <div class="kb-field"><strong>Check:</strong> Latch breakdown by class, identify hot pages</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">03_Storage_Engine/tempdb_configuration.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Depends on latch class - often related to memory, tempdb, or schema contention</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Variable</span></div>
    </div>
    <div class="kb-card" data-wait="ASYNC_NETWORK_IO">
      <h4>ASYNC_NETWORK_IO</h4>
      <div class="kb-field"><strong>Meaning:</strong> SQL Server waiting for the client application to consume results</div>
      <div class="kb-field"><strong>Symptoms:</strong> Large result sets, client application slow to process, chatty applications</div>
      <div class="kb-field"><strong>Check:</strong> Application-side processing, network latency, result set sizes</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">00_Framework/sp_DBA_ActiveSessions.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Optimize application code, reduce result sets, use pagination, check network</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Application-side issue</span></div>
    </div>
    <div class="kb-card" data-wait="PREEMPTIVE_OS">
      <h4>PREEMPTIVE_OS_*</h4>
      <div class="kb-field"><strong>Meaning:</strong> SQL Server calling an OS function and waiting for it to complete</div>
      <div class="kb-field"><strong>Symptoms:</strong> Slow backup/restore, slow DBCC, authentication delays</div>
      <div class="kb-field"><strong>Check:</strong> Identify specific PREEMPTIVE_OS wait subtype</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">00_Framework/sp_DBA_WaitAnalysis.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Depends on OS function - may indicate storage, network, or OS-level issue</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-y">Variable</span></div>
    </div>
    <div class="kb-card" data-wait="WAITFOR">
      <h4>WAITFOR / WAITFOR_DELAY</h4>
      <div class="kb-field"><strong>Meaning:</strong> Explicitly programmed wait (not a performance issue by itself)</div>
      <div class="kb-field"><strong>Symptoms:</strong> Appears in wait stats but is intentional</div>
      <div class="kb-field"><strong>Check:</strong> Review queries using WAITFOR statement</div>
      <div class="kb-field"><strong>Scripts:</strong> <span class="script-path">00_Framework/sp_DBA_WaitAnalysis.sql</span></div>
      <div class="kb-field"><strong>Fix:</strong> Usually benign; review if excessive and tied to specific applications</div>
      <div class="kb-field"><strong>Severity:</strong> <span class="tag tag-g">Usually benign</span></div>
    </div>
  </div>
</div>

<!-- ==================== SCRIPT EXPLORER ==================== -->
<div class="section-page" id="page-scriptExplorer">
  <div class="page-header">
    <h2>Script Explorer</h2>
    <p>Searchable catalog of all SQL scripts in the repository.</p>
  </div>
  <div class="card-box">
    <div style="margin-bottom:12px;">
      <input type="text" id="scriptSearchInput" placeholder="Search scripts by name, category, or keyword..." style="width:100%;padding:10px 14px;border:1px solid var(--border);border-radius:8px;background:var(--bg-hover);color:var(--text-primary);font-size:14px;" oninput="filterScripts()">
      <div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap;">
        <button class="btn-accent" onclick="filterScriptCategory('all')" style="font-size:11px;padding:4px 10px;">All</button>
        <button class="btn-accent" onclick="filterScriptCategory('Framework')" style="font-size:11px;padding:4px 10px;">Framework</button>
        <button class="btn-accent" onclick="filterScriptCategory('Server_OS')" style="font-size:11px;padding:4px 10px;">Server/OS</button>
        <button class="btn-accent" onclick="filterScriptCategory('Instance_Config')" style="font-size:11px;padding:4px 10px;">Config</button>
        <button class="btn-accent" onclick="filterScriptCategory('Storage_Engine')" style="font-size:11px;padding:4px 10px;">Storage</button>
        <button class="btn-accent" onclick="filterScriptCategory('Performance')" style="font-size:11px;padding:4px 10px;">Performance</button>
        <button class="btn-accent" onclick="filterScriptCategory('Index_Statistics')" style="font-size:11px;padding:4px 10px;">Index</button>
        <button class="btn-accent" onclick="filterScriptCategory('HA_DR')" style="font-size:11px;padding:4px 10px;">HA/DR</button>
        <button class="btn-accent" onclick="filterScriptCategory('Security')" style="font-size:11px;padding:4px 10px;">Security</button>
        <button class="btn-accent" onclick="filterScriptCategory('Advanced')" style="font-size:11px;padding:4px 10px;">Advanced</button>
        <button class="btn-accent" onclick="filterScriptCategory('Maintenance')" style="font-size:11px;padding:4px 10px;">Maintenance</button>
        <button class="btn-accent" onclick="filterScriptCategory('Preventive')" style="font-size:11px;padding:4px 10px;">Preventive</button>
      </div>
    </div>
    <table class="data-table" id="scriptTable">
      <thead>
        <tr>
          <th style="cursor:pointer" onclick="sortScriptTable(0)">Script <i class="fas fa-sort"></i></th>
          <th>Category</th>
          <th>Description</th>
          <th>Risk</th>
          <th>Prod Safe</th>
          <th>Environment</th>
          <th>Path</th>
        </tr>
      </thead>
      <tbody id="scriptTableBody"></tbody>
    </table>
  </div>
</div>

</div>

<!-- Search Overlay -->
<div class="search-overlay" id="searchOverlay" onclick="if(event.target===this)closeSearch()">
  <div class="search-box">
    <div style="display:flex;align-items:center;padding:0 16px;border-bottom:1px solid var(--border);">
      <i class="fas fa-search" style="color:var(--text-secondary);margin-right:10px;"></i>
      <input type="text" id="searchInput" placeholder="Search handbook..." oninput="performSearch()" autofocus>
      <button class="btn-icon" onclick="closeSearch()" style="border:none;width:28px;height:28px;"><i class="fas fa-times"></i></button>
    </div>
    <div class="search-results" id="searchResults"></div>
  </div>
</div>

<script>
const SCRIPT_BASE = '$scriptBase\\\\';

const scriptContents = {};

const scriptCatalog = [
  {name:'sp_DBA_HealthCheck.sql',cat:'Framework',desc:'Comprehensive health check - flagship procedure',risk:'Read Only',path:'00_Framework/sp_DBA_HealthCheck.sql'},
  {name:'sp_DBA_ActiveSessions.sql',cat:'Framework',desc:'Real-time active session monitor (DETAIL/SUMMARY/BLOCKING)',risk:'Read Only',path:'00_Framework/sp_DBA_ActiveSessions.sql'},
  {name:'sp_DBA_BackupReview.sql',cat:'Framework',desc:'Reviews backup history - dates, sizes, status',risk:'Read Only',path:'00_Framework/sp_DBA_BackupReview.sql'},
  {name:'sp_DBA_BaselineCapture.sql',cat:'Framework',desc:'Captures performance baseline for trend analysis',risk:'Read Only',path:'00_Framework/sp_DBA_BaselineCapture.sql'},
  {name:'sp_DBA_ForEachDatabase.sql',cat:'Framework',desc:'Utility to run commands against all user databases',risk:'Read Only',path:'00_Framework/sp_DBA_ForEachDatabase.sql'},
  {name:'sp_DBA_IndexReview.sql',cat:'Framework',desc:'Reviews index usage, fragmentation, and missing indexes',risk:'Read Only',path:'00_Framework/sp_DBA_IndexReview.sql'},
  {name:'sp_DBA_PlanCacheAnalyzer.sql',cat:'Framework',desc:'Deep plan cache analysis with anti-pattern detection',risk:'Read Only',path:'00_Framework/sp_DBA_PlanCacheAnalyzer.sql'},
  {name:'sp_DBA_QueryStoreRegressions.sql',cat:'Framework',desc:'Identifies Query Store regressions',risk:'Read Only',path:'00_Framework/sp_DBA_QueryStoreRegressions.sql'},
  {name:'sp_DBA_SaveAssessmentRun.sql',cat:'Framework',desc:'Persists health check results for historical comparison',risk:'Write',path:'00_Framework/sp_DBA_SaveAssessmentRun.sql'},
  {name:'sp_DBA_SecurityAudit.sql',cat:'Framework',desc:'Audits server and database-level security',risk:'Read Only',path:'00_Framework/sp_DBA_SecurityAudit.sql'},
  {name:'sp_DBA_WaitAnalysis.sql',cat:'Framework',desc:'Analyzes wait statistics to identify performance bottlenecks',risk:'Read Only',path:'00_Framework/sp_DBA_WaitAnalysis.sql'},
  {name:'fn_DBA_ExcludedWaitTypes.sql',cat:'Framework',desc:'Helper function listing wait types to exclude',risk:'Read Only',path:'00_Framework/fn_DBA_ExcludedWaitTypes.sql'},
  {name:'fn_DBA_AgentRunDurationSeconds.sql',cat:'Framework',desc:'Helper function for Agent job run durations',risk:'Read Only',path:'00_Framework/fn_DBA_AgentRunDurationSeconds.sql'},
  {name:'00_Deploy_Framework.sql',cat:'Framework',desc:'Deploy all framework objects',risk:'Write',path:'00_Framework/00_Deploy_Framework.sql'},
  {name:'00_Deploy_Framework.ps1',cat:'Framework',desc:'PowerShell deployment automation',risk:'Write',path:'00_Framework/00_Deploy_Framework.ps1'},
  {name:'00_Install_Framework.sql',cat:'Framework',desc:'Install DBA repository and all core objects',risk:'Write',path:'00_Framework/00_Install_Framework.sql'},
  {name:'cpu_utilization.sql',cat:'Server_OS',desc:'Historical CPU usage from ring buffers + Signal Wait analysis',risk:'Read Only',path:'01_Server_OS/cpu_utilization.sql'},
  {name:'disk_latency.sql',cat:'Server_OS',desc:'Disk I/O latency analysis',risk:'Read Only',path:'01_Server_OS/disk_latency.sql'},
  {name:'memory_diagnostics.sql',cat:'Server_OS',desc:'SQL Server memory diagnostics',risk:'Read Only',path:'01_Server_OS/memory_diagnostics.sql'},
  {name:'server_configuration_audit.sql',cat:'Instance_Config',desc:'Full server configuration audit',risk:'Read Only',path:'02_Instance_Config/server_configuration_audit.sql'},
  {name:'database_compatibility_audit.sql',cat:'Instance_Config',desc:'Database compatibility level audit',risk:'Read Only',path:'02_Instance_Config/database_compatibility_audit.sql'},
  {name:'os_integration_checks.sql',cat:'Instance_Config',desc:'OS integration checks for SQL Server',risk:'Read Only',path:'02_Instance_Config/os_integration_checks.sql'},
  {name:'database_files_growth.sql',cat:'Storage_Engine',desc:'Database file growth analysis',risk:'Read Only',path:'03_Storage_Engine/database_files_growth.sql'},
  {name:'tempdb_configuration.sql',cat:'Storage_Engine',desc:'TempDB configuration validation',risk:'Read Only',path:'03_Storage_Engine/tempdb_configuration.sql'},
  {name:'vlf_fragmentation.sql',cat:'Storage_Engine',desc:'Virtual Log File fragmentation analysis',risk:'Read Only',path:'03_Storage_Engine/vlf_fragmentation.sql'},
  {name:'blocking_and_deadlocks.sql',cat:'Performance',desc:'Blocking and deadlock pattern analysis',risk:'Read Only',path:'04_Performance_Diagnostics/blocking_and_deadlocks.sql'},
  {name:'deadlock_analysis.sql',cat:'Performance',desc:'Deep deadlock analysis with XML graphs',risk:'Read Only',path:'04_Performance_Diagnostics/deadlock_analysis.sql'},
  {name:'plan_cache_deep_dive.sql',cat:'Performance',desc:'Plan cache deep dive analysis',risk:'Read Only',path:'04_Performance_Diagnostics/plan_cache_deep_dive.sql'},
  {name:'top_resource_queries.sql',cat:'Performance',desc:'Top resource-consuming queries',risk:'Read Only',path:'04_Performance_Diagnostics/top_resource_queries.sql'},
  {name:'wait_statistics.sql',cat:'Performance',desc:'Wait statistics analysis',risk:'Read Only',path:'04_Performance_Diagnostics/wait_statistics.sql'},
  {name:'wait_statistics_reference.sql',cat:'Performance',desc:'Wait statistics reference guide',risk:'Read Only',path:'04_Performance_Diagnostics/wait_statistics_reference.sql'},
  {name:'advanced_index_analysis.sql',cat:'Index_Statistics',desc:'Advanced index analysis',risk:'Read Only',path:'05_Index_Statistics/advanced_index_analysis.sql'},
  {name:'index_usage_efficiency.sql',cat:'Index_Statistics',desc:'Index usage efficiency report',risk:'Read Only',path:'05_Index_Statistics/index_usage_efficiency.sql'},
  {name:'physical_stats_and_heaps.sql',cat:'Index_Statistics',desc:'Physical stats and heap analysis',risk:'Read Only',path:'05_Index_Statistics/physical_stats_and_heaps.sql'},
  {name:'statistics_freshness.sql',cat:'Index_Statistics',desc:'Statistics freshness check',risk:'Read Only',path:'05_Index_Statistics/statistics_freshness.sql'},
  {name:'alwayson_ag_monitor.sql',cat:'HA_DR',desc:'AlwaysOn AG monitoring',risk:'Read Only',path:'06_HA_DR/alwayson_ag_monitor.sql'},
  {name:'backup_log_chain.sql',cat:'HA_DR',desc:'Backup log chain integrity check',risk:'Read Only',path:'06_HA_DR/backup_log_chain.sql'},
  {name:'backup_verification.sql',cat:'HA_DR',desc:'Backup file verification',risk:'Read Only',path:'06_HA_DR/backup_verification.sql'},
  {name:'restore_test_simulator.sql',cat:'HA_DR',desc:'Restore test simulation',risk:'Write',path:'06_HA_DR/restore_test_simulator.sql'},
  {name:'authorization_audit.sql',cat:'Security',desc:'Authorization audit',risk:'Read Only',path:'07_Security/authorization_audit.sql'},
  {name:'encryption_hardening.sql',cat:'Security',desc:'Encryption hardening review',risk:'Read Only',path:'07_Security/encryption_hardening.sql'},
  {name:'login_audit.sql',cat:'Security',desc:'Login audit',risk:'Read Only',path:'07_Security/login_audit.sql'},
  {name:'cdc_health.sql',cat:'Advanced',desc:'CDC health check',risk:'Read Only',path:'08_Advanced/cdc_health.sql'},
  {name:'error_log_and_connectivity.sql',cat:'Advanced',desc:'Error log and connectivity check',risk:'Read Only',path:'08_Advanced/error_log_and_connectivity.sql'},
  {name:'feature_deep_dive_audit.sql',cat:'Advanced',desc:'Feature deep dive audit',risk:'Read Only',path:'08_Advanced/feature_deep_dive_audit.sql'},
  {name:'inmemory_compression.sql',cat:'Advanced',desc:'In-memory and compression analysis',risk:'Read Only',path:'08_Advanced/inmemory_compression.sql'},
  {name:'query_store_health.sql',cat:'Advanced',desc:'Query Store health check',risk:'Read Only',path:'08_Advanced/query_store_health.sql'},
  {name:'replication_monitor.sql',cat:'Advanced',desc:'Replication monitoring',risk:'Read Only',path:'08_Advanced/replication_monitor.sql'},
  {name:'sql_agent_job_monitor.sql',cat:'Advanced',desc:'SQL Agent job monitoring',risk:'Read Only',path:'08_Advanced/sql_agent_job_monitor.sql'},
  {name:'ultra_deep_internal_audit.sql',cat:'Advanced',desc:'Ultra deep internal audit',risk:'Read Only',path:'08_Advanced/ultra_deep_internal_audit.sql'},
  {name:'failed_jobs.sql',cat:'Maintenance',desc:'Failed SQL Agent jobs check',risk:'Read Only',path:'09_Maintenance/failed_jobs.sql'},
  {name:'last_checkdb_dates.sql',cat:'Maintenance',desc:'Last DBCC CHECKDB dates',risk:'Read Only',path:'09_Maintenance/last_checkdb_dates.sql'},
  {name:'database_growth_forecast.sql',cat:'Advanced',desc:'Database growth forecasting',risk:'Read Only',path:'10_Capacity_Planning/database_growth_forecast.sql'},
  {name:'regressed_queries.sql',cat:'Advanced',desc:'Query Store regressed queries',risk:'Read Only',path:'11_Query_Store/regressed_queries.sql'},
  {name:'active_xe_sessions.sql',cat:'Advanced',desc:'Active Extended Events sessions',risk:'Read Only',path:'12_Extended_Events/active_xe_sessions.sql'},
  {name:'resource_governor_config.sql',cat:'Advanced',desc:'Resource Governor configuration',risk:'Read Only',path:'13_Resource_Governor/resource_governor_config.sql'},
  {name:'performance_snapshot.sql',cat:'Advanced',desc:'Performance snapshot baseline',risk:'Read Only',path:'14_Baselines/performance_snapshot.sql'},
  {name:'01_Create_Governance_Database.sql',cat:'Preventive',desc:'Create governance database',risk:'Write',path:'preventive_measures/01_Create_Governance_Database.sql'},
  {name:'02_Capture_Running_Queries.sql',cat:'Preventive',desc:'Capture running queries',risk:'Read Only',path:'preventive_measures/02_Capture_Running_Queries.sql'},
  {name:'03_Check_Long_Running_Queries.sql',cat:'Preventive',desc:'Check long running queries',risk:'Read Only',path:'preventive_measures/03_Check_Long_Running_Queries.sql'},
  {name:'04_Check_Massive_DML.sql',cat:'Preventive',desc:'Check massive DML operations',risk:'Read Only',path:'preventive_measures/04_Check_Massive_DML.sql'},
  {name:'05_Check_Blocked_Applications.sql',cat:'Preventive',desc:'Check blocked applications',risk:'Read Only',path:'preventive_measures/05_Check_Blocked_Applications.sql'},
  {name:'06_Enforce_Query_Policy.sql',cat:'Preventive',desc:'Enforce query policies',risk:'Write',path:'preventive_measures/06_Enforce_Query_Policy.sql'},
  {name:'07_Setup_Extended_Events.sql',cat:'Preventive',desc:'Setup Extended Events monitoring',risk:'Write',path:'preventive_measures/07_Setup_Extended_Events.sql'},
  {name:'08_Alert_Management.sql',cat:'Preventive',desc:'Alert management configuration',risk:'Write',path:'preventive_measures/08_Alert_Management.sql'},
  {name:'09_Dashboard_Views.sql',cat:'Preventive',desc:'Create monitoring dashboard views',risk:'Write',path:'preventive_measures/09_Dashboard_Views.sql'},
  {name:'10_Create_SQL_Agent_Jobs.sql',cat:'Preventive',desc:'Create SQL Agent maintenance jobs',risk:'Write',path:'preventive_measures/10_Create_SQL_Agent_Jobs.sql'},
  {name:'11_Setup_Resource_Governor.sql',cat:'Preventive',desc:'Setup Resource Governor',risk:'Write',path:'preventive_measures/11_Setup_Resource_Governor.sql'},
  {name:'DBARepository_Create.sql',cat:'Framework',desc:'Creates DBA repository database schema',risk:'Write',path:'00_Repository/DBARepository_Create.sql'},
  {name:'DBARepository_Deploy.sql',cat:'Framework',desc:'Deploy repository database objects',risk:'Write',path:'00_Repository/DBARepository_Deploy.sql'},
  {name:'DBARepository_Persistence.sql',cat:'Framework',desc:'Repository persistence layer',risk:'Write',path:'00_Repository/DBARepository_Persistence.sql'},
  {name:'CheckIdRegistry.sql',cat:'Framework',desc:'Registry of health check IDs',risk:'Read Only',path:'00_Repository/CheckIdRegistry.sql'},
  {name:'AssessmentFindingTableType.sql',cat:'Framework',desc:'UDT for assessment results',risk:'Write',path:'00_Repository/AssessmentFindingTableType.sql'},
];

const sectionNames = {
  sec01:'01. DBA Principles',sec02:'02. First Responder',sec03:'03. Environment Discovery',
  sec04:'04. SQL Configuration',sec05:'05. Daily Health Checks',sec06:'06. Monitoring',
  sec07:'07. Incident Response',sec08:'08. Performance Tuning',sec09:'09. Blocking & Deadlocks',
  sec10:'10. Transaction Log',sec11:'11. Backup & Recovery',sec12:'12. Security Audit',
  sec13:'13. High Availability',sec14:'14. Disaster Recovery',sec15:'15. Capacity Planning',
  sec16:'16. Change Management',sec17:'17. Automation Scripts',sec18:'18. Case Studies',
  sec19:'19. RCA Templates',sec20:'20. DBA Growth Path',
  sec21:'21. Patch Management',sec22:'22. Data Corruption',sec23:'23. Wait Stats Reference'
};

const allSearchItems = [
  {text:'The First Rule: Collect evidence before changing anything',page:'sec01',section:'DBA Principles'},
  {text:'Never immediately restart, kill, shrink, or change configuration',page:'sec01',section:'DBA Principles'},
  {text:'5-Layer Diagnostic Model: Application > Query > Engine > OS > Hardware',page:'sec01',section:'DBA Principles'},
  {text:'Step 1: Is SQL Server Alive? Check connection, service, agent, cluster, AG',page:'sec02',section:'First Responder'},
  {text:'Step 2: Check Overall Health - CPU, Memory, Disk, Unexpected restart',page:'sec02',section:'First Responder'},
  {text:'Step 3: Check Current Blocking - blocking sessions, blocker activity',page:'sec02',section:'First Responder'},
  {text:'Step 4: Check Running Queries - long running, massive reads, bad plans',page:'sec02',section:'First Responder'},
  {text:'Server and Database Inventory',page:'sec03',section:'Environment Discovery'},
  {text:'RPO/RTO requirements documentation',page:'sec03',section:'Environment Discovery'},
  {text:'Server Configuration Audit',page:'sec04',section:'SQL Configuration'},
  {text:'Max server memory should not consume all OS memory',page:'sec04',section:'SQL Configuration'},
  {text:'MAXDOP and Cost Threshold for Parallelism',page:'sec04',section:'SQL Configuration'},
  {text:'TempDB: multiple files, equal size, fast storage',page:'sec04',section:'SQL Configuration'},
  {text:'Morning Health Check: service, agent, disk, CPU, memory, jobs, databases',page:'sec05',section:'Daily Health Checks'},
  {text:'Backup Validation: Full, Differential, Log, Restore test',page:'sec05',section:'Daily Health Checks'},
  {text:'Time-based workflow: Morning, During Day, Weekly, Monthly tasks',page:'sec05',section:'Daily Health Checks'},
  {text:'Active Monitoring, Extended Events, Query Store, Baselines',page:'sec06',section:'Monitoring'},
  {text:'Incident Response Flow: Alert > Evidence > Bottleneck > Fix > RCA',page:'sec07',section:'Incident Response'},
  {text:'Incident Priority Model P1 P2 P3 P4 severity classification',page:'sec07',section:'Incident Response'},
  {text:'Troubleshooting Decision Tree: interactive diagnostic flow',page:'sec07',section:'Incident Response'},
  {text:'Production Safety Check: verify server, database, permissions before execution',page:'sec07',section:'Incident Response'},
  {text:'Evidence Collection: incident snapshot, timestamp, blocking chain, wait stats',page:'sec07',section:'Incident Response'},
  {text:'Performance Tuning: collect query text, execution plan, waits, IO, CPU',page:'sec08',section:'Performance Tuning'},
  {text:'Blocking and Deadlock troubleshooting',page:'sec09',section:'Blocking & Deadlocks'},
  {text:'Transaction Log Full: check recovery model, log reuse wait',page:'sec10',section:'Transaction Log'},
  {text:'Backup & Recovery: RPO, RTO, restore testing',page:'sec11',section:'Backup & Recovery'},
  {text:'Security Audit: logins, permissions, SA account, encryption',page:'sec12',section:'Security Audit'},
  {text:'High Availability: AlwaysOn AG, Failover, Replication',page:'sec13',section:'High Availability'},
  {text:'Disaster Recovery: DR runbook, failover testing',page:'sec14',section:'Disaster Recovery'},
  {text:'Capacity Planning: growth forecasting, purge strategy',page:'sec15',section:'Capacity Planning'},
  {text:'Change Management: rollback plan, testing, approval',page:'sec16',section:'Change Management'},
  {text:'Automation: Framework deployment, utility procedures',page:'sec17',section:'Automation Scripts'},
  {text:'Case Studies: slow app, blocking storm, log full, CPU 100%, growth',page:'sec18',section:'Case Studies'},
  {text:'RCA Template: incident summary, root cause, resolution, prevention',page:'sec19',section:'RCA Templates'},
  {text:'DBA Growth Path: Junior to Senior career development',page:'sec20',section:'DBA Growth Path'},
  {text:'Patch Management: CU level, security patches, compatibility validation',page:'sec21',section:'Patch Management'},
  {text:'Upgrade checklist: backup, compatibility, deprecated features, monitoring',page:'sec21',section:'Patch Management'},
  {text:'Data Corruption: DBCC CHECKDB, page corruption, restore strategy, emergency mode',page:'sec22',section:'Data Corruption'},
  {text:'Wait Statistics Knowledge Base: PAGEIOLATCH, CXPACKET, WRITELOG, RESOURCE_SEMAPHORE',page:'sec23',section:'Wait Stats Reference'},
  {text:'WRITELOG: transaction log write bottleneck, storage configuration',page:'sec23',section:'Wait Stats Reference'},
  {text:'PAGEIOLATCH: disk I/O bottleneck, physical read/write latency',page:'sec23',section:'Wait Stats Reference'},
  {text:'CXPACKET: parallel query synchronization, MAXDOP tuning',page:'sec23',section:'Wait Stats Reference'},
  {text:'RESOURCE_SEMAPHORE: memory grant wait, query memory pressure',page:'sec23',section:'Wait Stats Reference'},
  {text:'LCK_M lock waits: blocking chains, isolation levels, lock escalation',page:'sec23',section:'Wait Stats Reference'},
  {text:'PAGELATCH: in-memory page contention, TempDB allocation',page:'sec23',section:'Wait Stats Reference'},
];

let currentScriptFilter = 'all';

function exportExcel() {
  const rows = [['Section', 'Task', 'Status', 'Script Reference', 'Priority']];
  document.querySelectorAll('.section-page').forEach(page => {
    const pageId = page.id.replace('page-', '');
    if (pageId === 'dashboard' || pageId === 'scriptExplorer') return;
    const sectionName = sectionNames[pageId] || pageId;
    page.querySelectorAll('.checklist-item').forEach(item => {
      const cb = item.querySelector('input[type="checkbox"]');
      if (!cb) return;
      const text = item.querySelector('.item-text');
      const script = item.querySelector('.item-script');
      const priority = item.querySelector('.priority-badge');
      rows.push([
        sectionName,
        text ? text.textContent.trim() : '',
        cb.checked ? 'Completed' : 'Not Started',
        script ? script.textContent.trim() : '',
        priority ? priority.textContent.trim() : ''
      ]);
    });
  });
  const csv = rows.map(r => r.map(c => '"' + c.replace(/"/g, '""') + '"').join(',')).join('\r\n');
  const bom = '\uFEFF';
  const dataUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(bom + csv);
  const a = document.createElement('a');
  a.setAttribute('href', dataUri);
  a.setAttribute('download', 'DBA_Production_Handbook_Checklist.csv');
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

function showPage(id, fromQuickAction) {
  document.querySelectorAll('.section-page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.sidebar-item').forEach(i => i.classList.remove('active'));
  const page = document.getElementById('page-' + id);
  if (page) page.classList.add('active');
  document.querySelectorAll('.sidebar-item').forEach(i => {
    if (i.getAttribute('onclick') && i.getAttribute('onclick').includes("'" + id + "'"))
      i.classList.add('active');
  });
  const backBtn = document.getElementById('backBtn');
  if (backBtn) backBtn.classList.toggle('visible', !!fromQuickAction);
  updateProgress();
  window.scrollTo(0, 0);
}

function toggleSidebar() {
  const sb = document.getElementById('sidebar');
  if (window.innerWidth <= 768) sb.classList.toggle('mobile-open');
  else sb.classList.toggle('collapsed');
}

function toggleTheme() {
  var html = document.documentElement;
  var btn = document.getElementById('themeBtn');
  if (html.getAttribute('data-theme') === 'dark') {
    html.setAttribute('data-theme', 'light');
    btn.textContent = '\uD83C\uDF19';
  } else {
    html.setAttribute('data-theme', 'dark');
    btn.textContent = '\u2600';
  }
}

function toggleDBAMode() {
  /* Toggles between Junior and Senior DBA modes.
     Junior (default): hides .senior-only elements for a simplified view.
     Senior: reveals .senior-only elements with advanced content. */
  var body = document.body;
  var sw = document.getElementById('dbamodeSwitch');
  if (body.classList.contains('mode-senior')) {
    body.classList.remove('mode-senior');
    body.classList.add('mode-junior');
    sw.classList.remove('active');
  } else {
    body.classList.remove('mode-junior');
    body.classList.add('mode-senior');
    sw.classList.add('active');
  }
}

function resetHandbook() {
  if (!confirm('Reset ALL checklist progress? This cannot be undone.')) return;
  var keys = [];
  for (var i = 0; i < localStorage.length; i++) {
    var k = localStorage.key(i);
    if (k && k.indexOf('dba_chk_') === 0) keys.push(k);
  }
  keys.forEach(function(k) { localStorage.removeItem(k); });
  document.querySelectorAll('.checklist-item input[type="checkbox"]').forEach(function(cb) {
    cb.checked = false;
    var notes = cb.closest('.checklist-item').querySelector('.notes-field');
    if (notes) notes.value = '';
  });
  updateProgress();
}

function saveCheck(cb) {
  const id = cb.getAttribute('data-id');
  const notes = cb.closest('.checklist-item').querySelector('.notes-field');
  const state = {
    checked: cb.checked,
    notes: notes ? notes.value : '',
    date: new Date().toISOString()
  };
  try { localStorage.setItem('dba_chk_' + id, JSON.stringify(state)); } catch(e) {}
  updateProgress();
}

function loadChecks() {
  document.querySelectorAll('.checklist-item input[type="checkbox"]').forEach(cb => {
    try {
      const saved = localStorage.getItem('dba_chk_' + cb.getAttribute('data-id'));
      if (saved) {
        const state = JSON.parse(saved);
        cb.checked = state.checked;
      }
    } catch(e) {}
  });
  updateProgress();
}

function updateProgress() {
  const total = document.querySelectorAll('.checklist-item input[type="checkbox"]').length;
  const checked = document.querySelectorAll('.checklist-item input[type="checkbox"]:checked').length;
  const pct = total > 0 ? Math.round((checked / total) * 100) : 0;
  document.getElementById('dashProgress').textContent = pct + '%';
  document.getElementById('dashCompleted').textContent = checked;
  document.getElementById('dashTotal').textContent = total;
  document.getElementById('dashProgressBar').style.width = pct + '%';
  document.getElementById('progressBadge').textContent = pct + '%';
  updateSectionProgress();
}

function updateSectionProgress() {
  const container = document.getElementById('sectionProgressList');
  if (!container) return;
  let html = '';
  for (const [key, name] of Object.entries(sectionNames)) {
    const page = document.getElementById('page-' + key);
    if (!page) continue;
    const items = page.querySelectorAll('.checklist-item input[type="checkbox"]');
    const total = items.length;
    if (total === 0) continue;
    let done = 0;
    items.forEach(i => { if (i.checked) done++; });
    const pct = Math.round((done / total) * 100);
    html += '<div style="display:flex;align-items:center;gap:12px;margin-bottom:8px;font-size:13px;">';
    html += '<span style="width:180px;flex-shrink:0;color:var(--text-secondary);">' + name + '</span>';
    html += '<div class="progress-bar-container" style="flex:1;"><div class="progress-bar-fill" style="width:' + pct + '%"></div></div>';
    html += '<span style="width:40px;text-align:right;font-weight:600;color:var(--accent);">' + pct + '%</span>';
    html += '</div>';
  }
  container.innerHTML = html;
}

function openSearch() {
  document.getElementById('searchOverlay').classList.add('active');
  const input = document.getElementById('searchInput');
  input.value = '';
  input.focus();
  document.getElementById('searchResults').innerHTML = '';
}

function closeSearch() {
  document.getElementById('searchOverlay').classList.remove('active');
}

function performSearch() {
  const q = document.getElementById('searchInput').value.toLowerCase().trim();
  const results = document.getElementById('searchResults');
  if (!q) { results.innerHTML = ''; return; }
  const matches = allSearchItems.filter(i => i.text.toLowerCase().includes(q) || i.section.toLowerCase().includes(q));
  if (matches.length === 0) {
    results.innerHTML = '<div style="padding:16px;color:var(--text-secondary);text-align:center;">No results found</div>';
    return;
  }
  results.innerHTML = matches.slice(0, 20).map(m =>
    '<div class="search-result-item" onclick="showPage(\'' + m.page + '\');closeSearch();"><div class="sr-section">' + m.section + '</div><div>' + m.text + '</div></div>'
  ).join('');
}

document.addEventListener('keydown', function(e) {
  if ((e.ctrlKey || e.metaKey) && e.key === 'k') { e.preventDefault(); openSearch(); }
  if (e.key === 'Escape') closeSearch();
});

function renderScriptTable() {
  const tbody = document.getElementById('scriptTableBody');
  if (!tbody) return;
  const searchVal = (document.getElementById('scriptSearchInput') ? document.getElementById('scriptSearchInput').value : '').toLowerCase();
  let filtered = scriptCatalog;
  if (currentScriptFilter !== 'all') {
    filtered = filtered.filter(s => s.cat === currentScriptFilter);
  }
  if (searchVal) {
    filtered = filtered.filter(s => s.name.toLowerCase().includes(searchVal) || s.desc.toLowerCase().includes(searchVal) || s.cat.toLowerCase().includes(searchVal));
  }
  tbody.innerHTML = filtered.map(s => {
    const riskClass = s.risk === 'Read Only' ? 'tag-g' : 'tag-y';
    const prodSafe = s.risk === 'Read Only' ? '<span class="tag tag-g">YES</span>' : '<span class="tag tag-y">REVIEW</span>';
    const envs = (s.env || 'prod,uat,dev').split(',');
    const envHtml = envs.map(e => {
      const cls = e.trim() === 'prod' ? 'env-prod' : e.trim() === 'uat' ? 'env-uat' : e.trim() === 'dev' ? 'env-dev' : 'env-dr';
      return '<span class="env-badge ' + cls + '">' + e.trim().toUpperCase() + '</span>';
    }).join(' ');
    return '<tr><td><strong>' + s.name + '</strong></td><td>' + s.cat + '</td><td>' + s.desc + '</td><td><span class="tag ' + riskClass + '">' + s.risk + '</span></td><td>' + prodSafe + '</td><td>' + envHtml + '</td><td class="script-path">' + SCRIPT_BASE + s.path + '</td></tr>';
  }).join('');
}

function filterScripts() { renderScriptTable(); }
function filterScriptCategory(cat) { currentScriptFilter = cat; renderScriptTable(); }
let scriptSortAsc = true;
function sortScriptTable(col) {
  scriptSortAsc = !scriptSortAsc;
  scriptCatalog.sort((a, b) => {
    const va = a.name.toLowerCase(), vb = b.name.toLowerCase();
    return scriptSortAsc ? va.localeCompare(vb) : vb.localeCompare(va);
  });
  renderScriptTable();
}

window.addEventListener('DOMContentLoaded', function() {
  loadChecks();
  renderScriptTable();
  updateProgress();
  initItemScriptClicks();
  var ts = document.getElementById('evidenceTimestamp');
  if (ts) ts.value = new Date().toISOString().replace('T',' ').substring(0,19);
});

function filterWaitTypes() {
  var q = (document.getElementById('waitSearchInput') ? document.getElementById('waitSearchInput').value : '').toLowerCase().trim();
  document.querySelectorAll('.kb-card[data-wait]').forEach(function(card) {
    var wait = (card.getAttribute('data-wait') || '').toLowerCase();
    var text = card.textContent.toLowerCase();
    if (!q || wait.includes(q) || text.includes(q)) {
      card.style.display = '';
    } else {
      card.style.display = 'none';
    }
  });
}

function collectEvidence() {
  var lines = [];
  lines.push('=== DBA INCIDENT SNAPSHOT ===');
  lines.push('Generated: ' + new Date().toISOString());
  lines.push('');
  var inputs = document.querySelectorAll('#page-sec07 .evidence-item input, #page-sec07 .evidence-item select');
  inputs.forEach(function(inp) {
    var label = inp.closest('.evidence-item');
    if (label) {
      var lbl = label.querySelector('label');
      if (lbl) lines.push(lbl.textContent.trim() + ': ' + (inp.value || '(not provided)'));
    }
  });
  lines.push('');
  lines.push('=== COLLECTED EVIDENCE ===');
  document.querySelectorAll('#page-sec07 .evidence-check-item input[type="checkbox"]').forEach(function(cb) {
    var lbl = cb.closest('.evidence-check-item');
    if (lbl) {
      var text = lbl.textContent.trim();
      lines.push((cb.checked ? '[x]' : '[ ]') + ' ' + text);
    }
  });
  lines.push('');
  lines.push('=== CHECKLIST STATUS ===');
  var total = document.querySelectorAll('.checklist-item input[type="checkbox"]').length;
  var checked = document.querySelectorAll('.checklist-item input[type="checkbox"]:checked').length;
  lines.push('Overall Progress: ' + checked + '/' + total + ' (' + Math.round((checked/total)*100) + '%)');
  lines.push('');
  lines.push('=== KEY SCRIPTS FOR INVESTIGATION ===');
  lines.push('Health Check: 00_Framework/sp_DBA_HealthCheck.sql');
  lines.push('Active Sessions: 00_Framework/sp_DBA_ActiveSessions.sql');
  lines.push('Wait Analysis: 00_Framework/sp_DBA_WaitAnalysis.sql');
  lines.push('Blocking: 04_Performance_Diagnostics/blocking_and_deadlocks.sql');
  lines.push('Top Queries: 04_Performance_Diagnostics/top_resource_queries.sql');
  lines.push('CPU: 01_Server_OS/cpu_utilization.sql');
  lines.push('Memory: 01_Server_OS/memory_diagnostics.sql');
  lines.push('Disk: 01_Server_OS/disk_latency.sql');
  lines.push('');
  lines.push('=== SNAPSHOT NOTE ===');
  lines.push('(Add incident notes here before exporting)');
  var blob = new Blob([lines.join('\n')], {type:'text/plain'});
  var a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  var ts = new Date().toISOString().substring(0,10);
  a.download = 'Incident_Report_' + ts + '.txt';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
}

/* ===== SQL Script Viewer Functions ===== */
function escapeHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function initItemScriptClicks() {
  document.querySelectorAll('.item-script').forEach(function(el) {
    el.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      var text = this.textContent.trim();
      var isFile = text.endsWith('.sql') || text.endsWith('.ps1');
      if (isFile) { viewScript(text, text.split('/').pop()); }
      else { viewInlineSQL(text); }
    });
  });
}

function viewInlineSQL(sqlText) {
  document.getElementById('viewerScriptName').textContent = 'SQL Snippet';
  document.getElementById('viewerRiskTag').textContent = 'Read Only';
  document.getElementById('viewerRiskTag').className = 'tag tag-g';
  document.getElementById('viewerCatTag').textContent = 'Inline';
  document.getElementById('viewerCatTag').className = 'tag tag-b';
  document.getElementById('viewerCode').innerHTML = highlightSQL(sqlText);
  document.getElementById('scriptViewerOverlay').classList.add('active');
}

function highlightSQL(code) {
  var tokens = [], result = code;
  result = result.replace(/\/\*[\s\S]*?\*\//g, function(m) { var i=tokens.length; tokens.push('<span class="sql-cmt">'+escapeHtml(m)+'</span>'); return '\x00C'+i+'\x00'; });
  result = result.replace(/--[^\r\n]*/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-cmt">'+escapeHtml(m)+'</span>'); return '\x00C'+i+'\x00'; });
  result = result.replace(/N'(?:[^']|'')*'/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-str">'+escapeHtml(m)+'</span>'); return '\x00S'+i+'\x00'; });
  result = result.replace(/'(?:[^']|'')*'/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-str">'+escapeHtml(m)+'</span>'); return '\x00S'+i+'\x00'; });
  result = result.replace(/@@\w+/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-var">'+escapeHtml(m)+'</span>'); return '\x00V'+i+'\x00'; });
  result = result.replace(/@\w+/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-var">'+escapeHtml(m)+'</span>'); return '\x00V'+i+'\x00'; });
  result = result.replace(/\bsys\.\w+/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-dmv">'+escapeHtml(m)+'</span>'); return '\x00D'+i+'\x00'; });
  result = result.replace(/\b(ALTER|AND|AS|ASC|BEGIN|BETWEEN|BY|CASE|CHECK|CLOSE|COLUMN|COMMIT|CONSTRAINT|CREATE|CROSS|CURSOR|DATABASE|DECLARE|DEFAULT|DELETE|DESC|DISTINCT|DROP|ELSE|END|EXEC|EXECUTE|EXISTS|FETCH|FOR|FOREIGN|FROM|FULL|FUNCTION|GROUP|HAVING|IF|IN|INDEX|INNER|INSERT|INTERSECT|INTO|IS|JOIN|KEY|LEFT|LIKE|NOT|NULL|OF|OFF|OFFSET|ON|OPEN|OPTION|OR|ORDER|OUTER|OVER|PARTITION|PRIMARY|PRINT|PROCEDURE|RAISERROR|RETURN|RIGHT|ROLLBACK|SELECT|SET|TABLE|THEN|TO|TOP|TRANSACTION|TRIGGER|TRUNCATE|UNION|UNIQUE|UPDATE|VALUES|VIEW|WHEN|WHERE|WHILE|WITH|NOCOUNT|QUOTED_IDENTIFIER|NOLOCK|APPLY|PIVOT|GO|TRY|CATCH|THROW)\b/gi, function(m) { var i=tokens.length; tokens.push('<span class="sql-kw">'+escapeHtml(m)+'</span>'); return '\x00K'+i+'\x00'; });
  result = result.replace(/\b(COUNT|SUM|AVG|MIN|MAX|COALESCE|NULLIF|ISNULL|CAST|CONVERT|DATEADD|DATEDIFF|DATEPART|GETDATE|OBJECT_ID|OBJECT_NAME|SERVERPROPERTY|HOST_NAME|USER_NAME|IS_MEMBER|PARSENAME|QUOTENAME|SUBSTRING|CHARINDEX|PATINDEX|LEN|ROUND|LTRIM|RTRIM|TRIM|REPLACE|STUFF|UPPER|LOWER|STRING_AGG|STRING_SPLIT|IIF|CONCAT)\b/gi, function(m) { var i=tokens.length; tokens.push('<span class="sql-fn">'+escapeHtml(m)+'</span>'); return '\x00F'+i+'\x00'; });
  result = result.replace(/\b(INT|BIGINT|SMALLINT|TINYINT|BIT|DECIMAL|NUMERIC|FLOAT|REAL|MONEY|DATE|TIME|DATETIME|DATETIME2|CHAR|VARCHAR|NCHAR|NVARCHAR|TEXT|NTEXT|BINARY|VARBINARY|UNIQUEIDENTIFIER|XML|CURSOR|TABLE)\b/gi, function(m) { var i=tokens.length; tokens.push('<span class="sql-type">'+escapeHtml(m)+'</span>'); return '\x00T'+i+'\x00'; });
  result = result.replace(/\b\d+\.?\d*\b/g, function(m) { var i=tokens.length; tokens.push('<span class="sql-num">'+escapeHtml(m)+'</span>'); return '\x00N'+i+'\x00'; });
  result = escapeHtml(result);
  for (var j=tokens.length-1;j>=0;j--) { ['\x00C','\x00S','\x00V','\x00D','\x00K','\x00F','\x00T','\x00N'].forEach(function(p){ result=result.replace(p+j+'\x00',tokens[j]); }); }
  return result;
}

function viewScript(path, name) {
  var content = scriptContents[path] || null;
  if (!content) { content = '-- Script content not available.\n-- File: ' + path + '\n-- Open this file directly to view the full SQL code.'; }
  var cat='', risk='';
  for (var i=0;i<scriptCatalog.length;i++) { if (scriptCatalog[i].path===path) { cat=scriptCatalog[i].cat; risk=scriptCatalog[i].risk; break; } }
  document.getElementById('viewerScriptName').textContent = name || path;
  document.getElementById('viewerRiskTag').textContent = risk;
  document.getElementById('viewerRiskTag').className = 'tag '+(risk==='Read Only'?'tag-g':'tag-y');
  document.getElementById('viewerCatTag').textContent = cat;
  document.getElementById('viewerCatTag').className = 'tag tag-b';
  document.getElementById('viewerCode').innerHTML = highlightSQL(content);
  document.getElementById('scriptViewerOverlay').classList.add('active');
}

function closeScriptViewer() { document.getElementById('scriptViewerOverlay').classList.remove('active'); }

function copyScriptContent() {
  var nameEl = document.getElementById('viewerScriptName');
  var content = '';
  if (nameEl && nameEl.textContent !== 'SQL Snippet') {
    var path = '';
    for (var i=0;i<scriptCatalog.length;i++) { if (scriptCatalog[i].name===nameEl.textContent) { path=scriptCatalog[i].path; break; } }
    content = scriptContents[path] || '';
  }
  if (!content) { var codeEl = document.getElementById('viewerCode'); if (codeEl) content=codeEl.textContent||''; }
  navigator.clipboard.writeText(content).then(function() {
    var btn = document.querySelector('.copy-btn');
    if (btn) { var o=btn.innerHTML; btn.innerHTML='<i class="fas fa-check"></i> Copied!'; setTimeout(function(){btn.innerHTML=o;},1500); }
  });
}

document.addEventListener('keydown', function(e) {
  if ((e.ctrlKey||e.metaKey)&&e.key==='k') { e.preventDefault(); openSearch(); }
  if (e.key==='Escape') {
    if (document.getElementById('scriptViewerOverlay').classList.contains('active')) closeScriptViewer();
    else closeSearch();
  }
});
</script>

<!-- Script Viewer Modal -->
<div class="script-viewer-overlay" id="scriptViewerOverlay" onclick="if(event.target===this)closeScriptViewer()">
  <div class="script-viewer">
    <div class="script-viewer-header">
      <h3 id="viewerTitle"><i class="fas fa-file-code"></i> <span id="viewerScriptName">script.sql</span></h3>
      <div class="script-viewer-actions">
        <span class="tag" id="viewerRiskTag">Read Only</span>
        <span class="tag" id="viewerCatTag">Framework</span>
        <button class="copy-btn" onclick="copyScriptContent()" title="Copy to clipboard"><i class="fas fa-copy"></i> Copy</button>
        <button class="btn-icon" onclick="closeScriptViewer()" style="border:none;width:28px;height:28px;"><i class="fas fa-times"></i></button>
      </div>
    </div>
    <div class="script-viewer-body">
      <pre class="sql-code" id="viewerCode"></pre>
    </div>
  </div>
</div>

</body>
</html>
"@

$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host "Done! Generated: $OutputPath" -ForegroundColor Green
Write-Host "Total checklist items mapped to scripts from the repository." -ForegroundColor Gray
