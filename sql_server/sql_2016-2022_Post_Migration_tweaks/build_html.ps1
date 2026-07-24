# Rebuild Compat160_Targeted_Fixes.html with embedded scripts + enhanced UI
# Run from anywhere:  powershell -File .\build_html.ps1
# Uses this script's folder as the package root (no hard-coded drive paths).
param(
    [string]$Base = $PSScriptRoot
)
$ErrorActionPreference = 'Stop'
if (-not $Base) { $Base = (Get-Location).Path }

function Escape-Json([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            '"' { [void]$sb.Append('\"') }
            '\' { [void]$sb.Append('\\') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 32) { [void]$sb.AppendFormat('\u{0:x4}', [int]$ch) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    return $sb.ToString()
}

$manifest = Get-Content (Join-Path $Base 'script_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$scriptParts = @()
foreach ($m in $manifest) {
    $path = Join-Path $Base ($m.key -replace '/', '\')
    if (-not (Test-Path $path)) { throw "Missing: $path" }
    $raw = [System.IO.File]::ReadAllText($path)
    $scriptParts += '  "' + $m.key + '": "' + (Escape-Json $raw) + '"'
}
$scriptContentsJs = "var scriptContents = {`n" + ($scriptParts -join ",`n") + "`n};"

$metaJson = $manifest | ConvertTo-Json -Depth 6 -Compress
$metaJs = "var scriptMeta = " + $metaJson + ";"

$outPath = Join-Path $Base 'Compat160_Targeted_Fixes.html'

$html = @'
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Compat 160 Performance Playbook  - SQL 2016 to 2022</title>
<style>
:root {
  --bg-primary:#0f1419; --bg-secondary:#1a1f2e; --bg-card:#1e2538; --bg-hover:#263044;
  --text-primary:#e1e5ee; --text-secondary:#8892a4; --accent:#3b82f6; --accent-hover:#2563eb;
  --accent-light:rgba(59,130,246,0.15); --success:#22c55e; --warning:#f59e0b; --danger:#ef4444;
  --border:#2d3748; --sidebar-width:268px; --header-height:64px;
}
[data-theme="light"] {
  --bg-primary:#f0f2f5; --bg-secondary:#ffffff; --bg-card:#ffffff; --bg-hover:#f5f7fa;
  --text-primary:#1a202c; --text-secondary:#4a5568; --accent:#0b6e4f; --accent-hover:#085c42;
  --accent-light:rgba(11,110,79,0.10); --border:#e2e8f0;
}
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',system-ui,sans-serif; background:var(--bg-primary); color:var(--text-primary); }
.header {
  position:fixed; top:0; left:0; right:0; height:var(--header-height);
  background:var(--bg-secondary); border-bottom:1px solid var(--border);
  display:grid; grid-template-columns:1fr auto 1fr; align-items:center;
  padding:0 20px; z-index:1000; gap:10px;
}
.header-brand h1 { font-size:15px; font-weight:700; line-height:1.25; }
.header-brand .subtitle { font-size:10px; color:var(--text-secondary); text-transform:uppercase; letter-spacing:0.4px; }
.header-actions { display:flex; gap:6px; justify-self:end; align-items:center; }
.btn-icon, .btn-accent, .btn-sm, .copy-btn {
  border-radius:8px; cursor:pointer; font-size:12px;
}
.btn-icon { width:36px; height:36px; border:1px solid var(--border); background:var(--bg-card); color:var(--text-secondary); }
.btn-accent { padding:6px 12px; border:none; background:var(--accent); color:#fff; font-weight:500; }
.btn-sm { padding:4px 9px; border:1px solid var(--border); background:var(--bg-hover); color:var(--text-secondary); }
.btn-sm.primary { background:var(--accent); color:#fff; border-color:var(--accent); }
.sidebar {
  position:fixed; top:var(--header-height); left:0; bottom:0; width:var(--sidebar-width);
  background:var(--bg-secondary); border-right:1px solid var(--border); overflow-y:auto; z-index:900;
}
.sidebar-label { padding:10px 18px; font-size:10px; font-weight:700; text-transform:uppercase; color:var(--text-secondary); }
.sidebar-item { padding:9px 18px; font-size:13px; color:var(--text-secondary); cursor:pointer; border-left:3px solid transparent; }
.sidebar-item:hover { background:var(--bg-hover); color:var(--text-primary); }
.sidebar-item.active { background:var(--accent-light); color:var(--accent); border-left-color:var(--accent); font-weight:600; }
.main-content { margin-left:var(--sidebar-width); margin-top:var(--header-height); padding:22px; min-height:calc(100vh - var(--header-height)); }
.section-page { display:none; max-width:1060px; }
.section-page.active { display:block; }
.page-header h2 { font-size:21px; margin-bottom:5px; }
.page-header p { color:var(--text-secondary); font-size:13px; margin-bottom:14px; }
.card-box { background:var(--bg-card); border:1px solid var(--border); border-radius:12px; padding:16px 18px; margin-bottom:14px; }
.card-box h3 { font-size:14px; margin-bottom:10px; }
.note, .note-warn { padding:11px 14px; border-radius:0 8px 8px 0; font-size:13px; margin-bottom:12px; }
.note { background:var(--accent-light); border-left:4px solid var(--accent); }
.note-warn { background:rgba(245,158,11,0.12); border-left:4px solid var(--warning); }
.search-bar { display:flex; gap:8px; flex-wrap:wrap; margin-bottom:12px; align-items:center; }
.search-bar input {
  flex:1; min-width:200px; padding:8px 12px; border-radius:8px; border:1px solid var(--border);
  background:var(--bg-hover); color:var(--text-primary); font-size:13px;
}
.tag-filters { display:flex; flex-wrap:wrap; gap:6px; margin-bottom:10px; }
.tag-btn {
  padding:4px 10px; border-radius:20px; border:1px solid var(--border); background:var(--bg-hover);
  font-size:11px; cursor:pointer; color:var(--text-secondary);
}
.tag-btn.active { background:var(--accent); color:#fff; border-color:var(--accent); }
.script-row {
  display:grid; grid-template-columns:1.4fr 1.6fr auto; gap:8px; align-items:start;
  padding:12px 0; border-bottom:1px solid var(--border); font-size:12px;
}
@media(max-width:800px){ .script-row { grid-template-columns:1fr; } }
.script-name { font-family:Consolas,monospace; color:var(--accent); cursor:pointer; font-weight:600; text-decoration:underline; }
.script-meta-line { display:flex; flex-wrap:wrap; gap:5px; margin-top:5px; }
.badge { font-size:10px; padding:2px 7px; border-radius:4px; font-weight:600; }
.badge-safe { background:rgba(34,197,94,0.15); color:var(--success); }
.badge-test { background:rgba(245,158,11,0.15); color:var(--warning); }
.badge-risk { background:rgba(239,68,68,0.15); color:var(--danger); }
.badge-ver { background:var(--bg-hover); color:var(--text-secondary); border:1px solid var(--border); }
.badge-tag { background:var(--accent-light); color:var(--accent); }
.deps { color:var(--text-secondary); font-size:11px; margin-top:4px; line-height:1.4; }
.flowchart { display:flex; flex-direction:column; gap:0; align-items:stretch; max-width:640px; }
.flow-node {
  border:1px solid var(--border); border-radius:10px; padding:12px 14px; background:var(--bg-card);
  cursor:pointer; transition:background .15s, border-color .15s;
}
.flow-node:hover { border-color:var(--accent); background:var(--accent-light); }
.flow-node.last-resort { border-color:var(--warning); }
.flow-node h4 { font-size:13px; margin-bottom:4px; }
.flow-node p { font-size:11px; color:var(--text-secondary); margin:0; }
.flow-arrow { text-align:center; color:var(--text-secondary); font-size:18px; padding:2px 0; }
.ref-list { list-style:none; }
.ref-list li { margin:8px 0; font-size:13px; }
.ref-list a { color:var(--accent); }
.script-viewer-overlay { display:none; position:fixed; inset:0; background:rgba(0,0,0,0.72); z-index:3000; align-items:center; justify-content:center; padding:16px; }
.script-viewer-overlay.active { display:flex; }
.script-viewer { width:96vw; max-width:1120px; max-height:92vh; background:var(--bg-card); border:1px solid var(--border); border-radius:12px; display:flex; flex-direction:column; overflow:hidden; }
.script-viewer-header { padding:12px 16px; border-bottom:1px solid var(--border); display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap; }
.viewer-meta { font-size:11px; color:var(--text-secondary); margin-top:6px; line-height:1.5; }
.script-viewer-body { flex:1; overflow:auto; }
.sql-code { margin:0; padding:14px 18px; font-family:Consolas,monospace; font-size:12px; line-height:1.55; white-space:pre; background:#1e1e1e; color:#d4d4d4; }
code { font-family:Consolas,monospace; font-size:0.9em; background:var(--bg-hover); color:var(--text-primary); padding:1px 5px; border-radius:4px; }
pre { margin:0; background:#1e1e1e; border:1px solid var(--border); border-radius:8px; padding:12px 14px; overflow:auto; }
pre code { background:none; color:#d4d4d4; padding:0; font-size:12px; line-height:1.55; white-space:pre; }
.copy-btn { padding:5px 11px; border:1px solid var(--border); background:var(--bg-hover); color:var(--text-primary); }
.copy-btn.accent { background:var(--accent); color:#fff; border-color:var(--accent); }
.cat-header { font-size:10px; font-weight:700; text-transform:uppercase; color:var(--text-secondary); margin:12px 0 6px; padding-top:8px; border-top:1px solid var(--border); }
.cat-header:first-child { border-top:none; padding-top:0; margin-top:0; }
table.tech { width:100%; border-collapse:collapse; font-size:12px; }
table.tech th, table.tech td { padding:8px; border-bottom:1px solid var(--border); text-align:left; vertical-align:top; }
table.tech th { background:var(--bg-hover); }
.guide-progress {
  height:8px; background:var(--border); border-radius:4px; overflow:hidden; margin:10px 0 6px;
}
.guide-progress-fill { height:100%; background:linear-gradient(90deg,var(--accent),var(--success)); width:0%; transition:width .3s; }
.guide-step-list { list-style:none; margin:0; padding:0; }
.guide-step-list li {
  display:flex; align-items:flex-start; gap:10px; padding:8px 0; border-bottom:1px solid var(--border);
  font-size:12px; color:var(--text-secondary); cursor:pointer;
}
.guide-step-list li:hover { color:var(--text-primary); }
.guide-step-list li.active { color:var(--accent); font-weight:600; }
.guide-step-list li.done { color:var(--success); }
.guide-step-list .gnum {
  flex-shrink:0; width:22px; height:22px; border-radius:50%; border:1px solid var(--border);
  display:flex; align-items:center; justify-content:center; font-size:10px; font-weight:700;
}
.guide-step-list li.active .gnum { background:var(--accent); color:#fff; border-color:var(--accent); }
.guide-step-list li.done .gnum { background:var(--success); color:#fff; border-color:var(--success); }
.guide-panel { border:1px solid var(--border); border-radius:12px; padding:18px; background:var(--bg-card); }
.guide-panel h3 { font-size:16px; margin-bottom:8px; }
.guide-why, .guide-do, .guide-pass, .guide-fail {
  font-size:13px; line-height:1.55; margin:10px 0; color:var(--text-secondary);
}
.guide-why strong, .guide-do strong, .guide-pass strong, .guide-fail strong { color:var(--text-primary); }
.guide-actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
.btn-success { background:var(--success) !important; color:#fff !important; border-color:var(--success) !important; }
.btn-next { background:var(--warning) !important; color:#1a202c !important; border-color:var(--warning) !important; }
.guide-done-box {
  display:none; padding:20px; border-radius:12px; border:1px solid var(--success);
  background:rgba(34,197,94,0.12); font-size:14px; line-height:1.6;
}
.guide-done-box.show { display:block; }
.guide-layout { display:grid; grid-template-columns:220px 1fr; gap:16px; }
@media(max-width:900px){ .guide-layout { grid-template-columns:1fr; } }
@media(max-width:768px){ .sidebar{transform:translateX(-100%);}.sidebar.open{transform:translateX(0);}.main-content{margin-left:0;} }
</style>
</head>
<body>
<div class="header">
  <div><button class="btn-icon" onclick="document.getElementById('sidebar').classList.toggle('open')">&#9776;</button></div>
  <div class="header-brand" style="text-align:center">
    <h1>Compat 160 Performance Playbook</h1>
    <div class="subtitle">SQL 2016 &#8594; 2022 &bull; Diagnose before hints</div>
  </div>
  <div class="header-actions">
    <button class="btn-icon" onclick="toggleTheme()">&#127769;</button>
    <button class="btn-accent" onclick="showPage('guided')">Guided steps</button>
    <button class="btn-accent" onclick="showPage('scripts')">Scripts</button>
  </div>
</div>
<nav class="sidebar" id="sidebar">
  <div class="sidebar-label">Guide</div>
  <div class="sidebar-item active" data-page="overview" onclick="showPage('overview')">Overview</div>
  <div class="sidebar-item" data-page="guided" onclick="showPage('guided')">Guided approach</div>
  <div class="sidebar-item" data-page="flow" onclick="showPage('flow')">Methodology flow</div>
  <div class="sidebar-item" data-page="path" onclick="showPage('path')">Fix path @ CL 160</div>
  <div class="sidebar-item" data-page="settings" onclick="showPage('settings')">Settings explained (FAQ)</div>
  <div class="sidebar-item" data-page="refs" onclick="showPage('refs')">References</div>
  <div class="sidebar-label">Scripts</div>
  <div class="sidebar-item" data-page="scripts" onclick="showPage('scripts')">Script library</div>
</nav>
<main class="main-content">

<div class="section-page active" id="page-overview">
  <div class="page-header">
    <h2>Overview</h2>
    <p>
      This playbook targets a very specific, common scenario: databases restored from SQL Server 2016 onto SQL Server 2022
      run fine at <code>compatibility_level 130</code>, but the application slows down once the level is raised to <code>160</code>.
      Compatibility 160 switches on a newer Cardinality Estimator, newer optimizer transformations, and Intelligent Query
      Processing all at once, so plans that were healthy under 2016 can suddenly get worse estimates, join choices, and memory grants.
      The goal here is to <strong>diagnose the real cause first</strong> (server config, statistics, CE, parameter sniffing, or IQP)
      and remediate surgically while <strong>staying on CL 160</strong>, treating Legacy CE and full rollback to 130 as last resorts.
      Everything you need is on this page and in the sidebar - work top to bottom, or jump straight to the guided approach.
    </p>
  </div>

  <div class="card-box">
    <h3>Typical root cause</h3>
    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:8px">
      Slowness at CL 160 is usually <strong style="color:var(--text-primary)">not a broken install</strong>.
      Compatibility 160 enables a newer Cardinality Estimator (CE), different optimizer transformations, and
      Intelligent Query Processing (IQP). Plans that worked under CE 130 can get worse row estimates under CE 160,
      leading to different join types, memory grants, spills, and parameter-sensitive plan changes.
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li>CE estimate changes on joins, filters, and correlated predicates</li>
      <li>IQP features turned on together when skipping 2017/2019: UDF inlining, batch mode on rowstore, PSP</li>
      <li>Parameter sniffing amplified on skewed data</li>
      <li>Implicit conversions and non-SARGable SQL exposed by new plan choices</li>
      <li>Post-restore: stale 2016 stats / row counts if FULLSCAN + DBCC UPDATEUSAGE were skipped</li>
    </ul>
  </div>

  <div class="card-box">
    <h3>Backup/restore nuances (2016 -&gt; 2022)</h3>
    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:8px">
      Restore carries over 2016 statistics headers and modification counters. Jumping to CL 160 also activates
      SQL 2019 + 2022 IQP features the app never saw under 2016. New hosts often change core/NUMA counts, so
      CTFP (raise from default 5 to 30-50) and MAXDOP must be re-baselined.
      On engagements where stats/indexes/MAXDOP are already done, keep these steps as a checklist for the next migration.
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.65">
      <li><strong>Post-restore:</strong> <code>DBCC UPDATEUSAGE(0)</code> then <code>UPDATE STATISTICS ... WITH FULLSCAN</code> before CL 160</li>
      <li><strong>Instance:</strong> CTFP 30-50, MAXDOP per NUMA physical cores, optimize for ad hoc = 1</li>
      <li><strong>Widespread CL 160 pain:</strong> Legacy CE / UDF inlining OFF / optimizer hotfixes as scoped bridges</li>
    </ul>
    <div style="margin-top:10px">
      <button class="btn-sm primary" onclick="viewScript('04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql')">Post-restore maintenance</button>
      <button class="btn-sm" onclick="viewScript('02_Configuration/01_Recommended_Instance_Settings_2022.sql')">Instance settings</button>
      <button class="btn-sm" onclick="viewScript('05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql')">IQP skip-release notes</button>
    </div>
  </div>

  <div class="card-box">
    <h3>What this playbook does</h3>
    <ul style="margin-left:18px;font-size:13px;line-height:1.65">
      <li><strong>Diagnose before hints</strong> - rule out server config, blocking, stats, CE, sniffing, and IQP layers</li>
      <li><strong>Capture baselines</strong> - Query Store golden plans at CL 130 before flipping UAT/prod to 160</li>
      <li><strong>Find regressions</strong> - compare duration, CPU, logical reads, and waits before vs after</li>
      <li><strong>Remediate surgically</strong> - plan force, Query Store hints (SQL 2022), IQP isolation, targeted rewrites</li>
      <li><strong>Cut over safely</strong> - controlled move to CL 160 with rollback and monitoring scripts</li>
    </ul>
  </div>

  <div class="card-box">
    <h3>How to run it</h3>
    <ol style="margin-left:18px;font-size:13px;line-height:1.75">
      <li><strong>Open this HTML</strong> in a browser (Chrome/Edge). Use the sidebar or <em>Script library</em>.</li>
      <li><strong>Follow the methodology flow</strong> top to bottom. Click a step to open its recommended script.</li>
      <li><strong>View or Download</strong> a script, open SSMS, replace <code>[YourDB]</code> and date windows where marked.</li>
      <li><strong>Run read-only diagnostics first</strong> on UAT. Scripts show safety level (Safe / Test First / High Risk).</li>
      <li><strong>Keep production at CL 130</strong> until Query Store has 3-7 days of baseline at 130, then test 160 in UAT.</li>
      <li><strong>Do not flip prod to 160</strong> without Query Store or equivalent before/after comparison.</li>
    </ol>
    <div style="margin-top:12px">
      <button class="btn-sm primary" onclick="showPage('guided')">Start guided approach (juniors)</button>
      <button class="btn-sm" onclick="viewScript('03_QueryStore_PlanForce/01_Enable_QueryStore.sql')">Enable Query Store</button>
      <button class="btn-sm" onclick="showPage('flow')">Methodology flow</button>
      <button class="btn-sm" onclick="showPage('scripts')">Browse all scripts</button>
    </div>
  </div>

  <div class="note-warn">
    <strong>Consulting rule:</strong> Determine whether slowness is Server config, Engine (blocking/waits), CE, Statistics,
    Parameter sniffing, IQP, or Application <em>before</em> query hints or Legacy CE. Hints and plan force are last resorts.
  </div>

  <div class="card-box">
    <h3>Fastest safe path (from Quick Start)</h3>
    <ol style="margin-left:18px;font-size:13px;line-height:1.65">
      <li>Post-restore baseline: UPDATEUSAGE + stats FULLSCAN; set CTFP/MAXDOP/ad hoc on the new host.</li>
      <li>Keep production at CL 130; enable Query Store and capture workload (3-7 days).</li>
      <li>On UAT, set <code>COMPATIBILITY_LEVEL = 160</code>, clear proc cache, run the automatic regression report.</li>
      <li>Few regressions: force last-good plan or apply Query Store hints (no app deploy on SQL 2022).</li>
      <li>Many regressions: Legacy CE and/or disable UDF inlining / isolate one IQP feature - keep CL 160.</li>
      <li>Rewrite stubborn SQL; remove temporary bridges; move production to 160 in a change window.</li>
    </ol>
    <p style="font-size:12px;color:var(--text-secondary);margin-top:10px">
      Emergency rollback: <code>ALTER DATABASE [YourDB] SET COMPATIBILITY_LEVEL = 130;</code>
    </p>
  </div>

  <div class="card-box">
    <h3>What this file is</h3>
    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:10px">
      This is a self-contained HTML runbook for DBAs and consultants. It packages diagnostic SQL, remediation scripts,
      a methodology flowchart, and Microsoft/community references for the common scenario: databases restored from
      SQL Server 2016 onto SQL Server 2022, application stable at <code>compatibility_level 130</code>, but slower after
      moving to <code>160</code>.
    </p>
    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary)">
      All scripts are <strong>embedded</strong> in this HTML (View / Copy / Download work offline with no folder path required).
      Companion markdown guides live under <code>docs/</code> (relative to this HTML):
      <code>docs/00_README_Troubleshooting_Playbook.md</code>,
      <code>docs/QUICK_START.md</code>,
      <code>docs/CLIENT_CUTOVER_CHECKLIST.md</code>,
      <code>docs/BACKUP_RESTORE_NUANCES_2016_to_2022.md</code>,
      <code>docs/HOW_TO_SHARE.md</code>.
    </p>
    <p style="font-size:12px;line-height:1.55;color:var(--text-secondary);margin-top:8px">
      <strong>Sharing:</strong> Zip this entire folder and send it. Recipients should unzip, then open
      <code>Compat160_Targeted_Fixes.html</code> from the unzipped root. No drive letters or machine-specific paths are used.
      Loose <code>.sql</code> files also sit under relative folders (<code>01_Diagnostics/</code>, <code>03_QueryStore_PlanForce/</code>, etc.).
      Documentation is in <code>docs/</code>.
    </p>
  </div>
</div>

<div class="section-page" id="page-guided">
  <div class="page-header">
    <h2>Guided approach (for junior DBAs)</h2>
    <p>Follow steps in order - like an expert mentor. Complete each step, then choose whether it fixed the issue or you must continue.</p>
  </div>
  <div class="note">
    <strong>Rule:</strong> Do not skip ahead. Do not apply query hints or Legacy CE until Step 9+.
    Work in <strong>UAT first</strong>. Keep production at CL 130 until you have a Query Store baseline.
  </div>
  <div class="card-box" style="margin-bottom:12px">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">
      <span style="font-size:13px"><strong>Progress:</strong> <span id="guideProgressLabel">Step 1 of 10</span></span>
      <button class="btn-sm" onclick="resetGuided()">Reset guided progress</button>
    </div>
    <div class="guide-progress"><div class="guide-progress-fill" id="guideProgressBar"></div></div>
  </div>
  <div class="guide-layout">
    <div class="card-box" style="margin:0">
      <h3>Steps</h3>
      <ul class="guide-step-list" id="guideStepList"></ul>
    </div>
    <div>
      <div class="guide-panel" id="guidePanel"></div>
      <div class="guide-done-box" id="guideDoneBox">
        <strong>Resolved - good work.</strong><br>
        Document what fixed it (script used, scoped config, forced plan_id, or rewrite).
        Keep monitoring for 24-48 hours with the post-cutover health check.
        If you only used a temporary bridge (Legacy CE / UDF inlining OFF), open a follow-up ticket to remove it after a permanent fix.
        <div class="guide-actions">
          <button class="btn-sm primary" onclick="viewScript('07_Monitoring_Baseline/02_Post_Cutover_Health_Check.sql')">Post-cutover health check</button>
          <button class="btn-sm" onclick="resetGuided()">Start over</button>
        </div>
      </div>
    </div>
  </div>
</div>

<div class="section-page" id="page-flow">
  <div class="page-header">
    <h2>Methodology flow</h2>
    <p>Click a step to open the recommended script. Only proceed down when the layer is ruled out or fixed.</p>
  </div>
  <div class="flowchart" id="flowchart"></div>
  <div class="note" style="margin-top:16px">
    <strong>Hints / Legacy CE / plan force</strong> sit at the bottom intentionally. Microsoft Learn and field consultants treat them as controlled mitigations after diagnosis.
  </div>
</div>

<div class="section-page" id="page-path">
  <div class="page-header"><h2>Fix path at CL 160</h2><p>After methodology confirms CE/IQP layer.</p></div>
  <div class="card-box">
    <ol style="margin-left:18px;font-size:13px;line-height:1.7">
      <li>Run <button class="btn-sm primary" onclick="viewScript('03_QueryStore_PlanForce/05_Automatic_Regression_Report.sql')">Automatic regression report</button></li>
      <li>Few queries -> QS hint or force plan</li>
      <li>Many queries -> isolate one IQP feature; temp Legacy CE only as bridge</li>
      <li>Enable Automatic Tuning; rewrite stubborn SQL; remove bridges</li>
    </ol>
  </div>
</div>

<div class="section-page" id="page-settings">
  <div class="page-header">
    <h2>Settings explained (FAQ)</h2>
    <p>Deep dive on the two database-scoped toggles clients ask about most: <code>TSQL_SCALAR_UDF_INLINING = OFF</code> and <code>LEGACY_CARDINALITY_ESTIMATION = ON</code>. What each one is, why you would use it, the consequences, and how to troubleshoot further.</p>
  </div>

  <div class="note">
    <strong>Read this first - the mental model.</strong> Compatibility level 160 bundles three separate things together:
    (1) the <strong>Cardinality Estimator (CE)</strong> version, (2) <strong>Intelligent Query Processing (IQP)</strong> features such as scalar UDF inlining and batch mode, and (3) optimizer/parser behavior.
    The two settings below let you turn off <em>one piece at a time</em> and keep the database at CL 160, instead of rolling the whole database back to 130. That is why they are "surgical bridges", not permanent fixes. Both are <strong>database-scoped configurations</strong>, not query hints - the client's application code and stored procedures do not change.
  </div>

  <!-- ======================= UDF INLINING ======================= -->
  <div class="card-box">
    <h3>1. TSQL_SCALAR_UDF_INLINING = OFF</h3>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:10px">
      <strong style="color:var(--text-primary)">What it is.</strong>
      Scalar UDF inlining is an IQP feature introduced in SQL Server 2019 and active at CL 150+. When ON (the default at CL 160),
      the optimizer rewrites the body of a scalar user-defined function (e.g. <code>dbo.fn_CalcTax(...)</code>) directly into the
      calling query, so the whole statement gets one combined execution plan instead of running the function row-by-row.
      Setting <code>TSQL_SCALAR_UDF_INLINING = OFF</code> turns that rewrite off and returns to the classic SQL 2016 behavior
      where the scalar UDF executes once per row.
    </p>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:10px">
      <strong style="color:var(--text-primary)">Why turning it OFF can help.</strong>
      Inlining is usually a win, but for some functions it backfires and is a very common cause of post-CL-160 slowness:
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li><strong>Bad cost/estimates on complex UDFs</strong> - functions with many statements, <code>WHILE</code> loops, or data access get inlined into a giant, hard-to-estimate plan that the optimizer costs poorly.</li>
      <li><strong>Huge / slow-to-compile plans</strong> - inlining a UDF used in many places can explode plan size and increase compile time and memory grants.</li>
      <li><strong>Different (worse) join or memory-grant choices</strong> - the combined plan picks a strategy that was never a problem when the UDF ran separately.</li>
      <li><strong>Timeouts that only appear at CL 160</strong> - the same query text runs fine at 130/150-without-inlining but regresses once inlined.</li>
    </ul>
    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      Turning inlining OFF keeps the database at CL 160 (so you retain every other 2022 improvement) while removing just this
      one behavior, restoring the SQL 2016 execution pattern for scalar UDFs.
    </p>

    <div class="note">
      <strong>Use case (when to reach for it).</strong> You confirmed via diagnostics that regressed queries call scalar UDFs,
      the plans show inlined function logic, and disabling inlining in a test restores performance. Ideal when many objects are
      affected and you cannot rewrite them all immediately.
    </div>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">Consequences / trade-offs.</strong>
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li>UDFs that <em>did</em> benefit from inlining lose that benefit database-wide (this is a blunt, DB-level switch).</li>
      <li>It masks the root cause - the real fix is rewriting scalar UDFs as inline table-valued functions (iTVFs) or set-based logic.</li>
      <li>Scope is the whole database; you cannot inline some UDFs and not others with this switch (use <code>OPTION(USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'))</code> or the <code>INLINE = OFF</code> function option for per-object control).</li>
    </ul>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">Scoping it tighter (preferred order).</strong>
      Per-statement hint &rarr; per-function <code>WITH INLINE = OFF</code> &rarr; database-scoped OFF (broadest). Start narrow.
    </p>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">How to troubleshoot further.</strong>
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li>List inlineable functions and confirm which are actually being inlined.</li>
      <li>Compare a regressed query with inlining ON vs OFF and diff the plans and metrics.</li>
      <li>Long term, convert hot scalar UDFs to iTVFs / set-based code, then re-enable inlining.</li>
    </ul>
    <div style="margin-top:10px">
      <button class="btn-sm primary" onclick="viewScript('05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql')">Inspect UDF inlining status</button>
      <button class="btn-sm" onclick="viewScript('05_Compatibility_CE_Controls/05_IQP_Feature_Isolation_Toggles.sql')">Isolate IQP features</button>
      <button class="btn-sm" onclick="viewScript('06_Code_Rewrite_Patterns/01_Before_After_Examples.sql')">Rewrite patterns</button>
    </div>
    <pre style="margin-top:12px"><code>-- Database-wide (blunt) - keeps CL 160, disables only UDF inlining:
ALTER DATABASE SCOPED CONFIGURATION SET TSQL_SCALAR_UDF_INLINING = OFF;

-- Narrower: single query
SELECT ... OPTION (USE HINT('DISABLE_TSQL_SCALAR_UDF_INLINING'));

-- Narrowest: single function
ALTER FUNCTION dbo.fn_Example (...) WITH INLINE = OFF ...;</code></pre>
  </div>

  <!-- ======================= LEGACY CE ======================= -->
  <div class="card-box">
    <h3>2. LEGACY_CARDINALITY_ESTIMATION = ON</h3>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:10px">
      <strong style="color:var(--text-primary)">What it does.</strong>
      The Cardinality Estimator is the part of the optimizer that predicts how many rows each operator will produce.
      SQL Server 2014 introduced a "new CE"; SQL 2016/2019/2022 refined it further. At CL 160 the database uses the
      <em>newest</em> CE. Setting <code>LEGACY_CARDINALITY_ESTIMATION = ON</code> tells the optimizer to use the
      <strong>SQL Server 2012-and-earlier "legacy" (CE 70) row-estimation model</strong> while keeping the database at CL 160.
      It is the database-scoped equivalent of the trace flag 9481 / <code>USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION')</code>.
    </p>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-bottom:10px">
      <strong style="color:var(--text-primary)">Why you might need it.</strong>
      The new CE makes different assumptions (independence vs correlation of predicates, ascending-key handling, join
      containment). On some schemas - especially older ones designed against the legacy CE - these assumptions produce
      worse estimates, which cascade into wrong join types, undersized/oversized memory grants, and spills. When a broad set
      of queries regress at CL 160 and diagnostics point at estimate changes (not blocking, not stats, not UDFs), the legacy
      CE can restore the SQL 2016-era estimates immediately without an application change.
    </p>

    <div class="note-warn">
      <strong>"Will this set all the CE back to 2016?" - Important clarification.</strong>
      Not exactly. It does <em>not</em> revert the database to compatibility level 130, and it is <em>not</em> the same CE that CL 130 used.
      CL 130 runs the <strong>CE 130</strong> model; <code>LEGACY_CARDINALITY_ESTIMATION = ON</code> forces the even older
      <strong>CE 70 (legacy / pre-2014)</strong> model. It changes only the <em>cardinality estimation</em> component - all other
      CL 160 behavior (IQP, optimizer transformations, parser features) stays active. So it is broader than a single query hint
      (it affects <em>every</em> query in the database) but narrower than a full compatibility-level rollback.
    </div>

    <div class="note">
      <strong>Use case (when to reach for it).</strong> Many queries regress after moving to CL 160, plan comparisons show the
      difference is in <em>row estimates</em>, and testing with <code>FORCE_LEGACY_CARDINALITY_ESTIMATION</code> on a few of them
      restores performance. Use it as a temporary bridge to keep CL 160 in production while you fix root causes.
    </div>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">Consequences / trade-offs.</strong>
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li><strong>Database-wide blunt instrument</strong> - every query now estimates with the old model, including ones that were <em>faster</em> under the new CE. You may fix 20 queries and slow down 5 others.</li>
      <li><strong>You lose newer CE improvements</strong> - better handling of modern workloads, some IQP features rely on good estimates.</li>
      <li><strong>It hides the real problem</strong> - usually stale statistics, missing/multi-column stats, skew, or non-SARGable SQL. Legacy CE just papers over the estimate.</li>
      <li><strong>Not a permanent answer</strong> - Microsoft guidance is to stay on the current CE and remediate; treat this as a stabilizer while you do targeted work (Query Store hints, plan forcing, rewrites).</li>
    </ul>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">Prefer narrower scope first.</strong>
      Before flipping the whole database, force legacy CE on just the offending queries via a Query Store hint (SQL 2022, no code change)
      or <code>OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'))</code>. Only go database-wide if regressions are widespread.
    </p>

    <p style="font-size:13px;line-height:1.65;color:var(--text-secondary);margin-top:10px">
      <strong style="color:var(--text-primary)">How to troubleshoot further.</strong>
    </p>
    <ul style="margin-left:18px;font-size:13px;line-height:1.6;color:var(--text-secondary)">
      <li>Compare CE 130 vs CE 160 estimates on the regressed queries and confirm the gap is in estimated rows.</li>
      <li>Fix inputs to the CE first: <code>UPDATE STATISTICS ... WITH FULLSCAN</code>, add missing/multi-column statistics, remove implicit conversions and functions on columns (SARGability).</li>
      <li>Use Query Store to force last-good plans or apply per-query legacy-CE hints instead of the DB-wide switch.</li>
      <li>Re-test with legacy CE OFF after fixing stats/SQL; the goal is to remove the bridge.</li>
    </ul>
    <div style="margin-top:10px">
      <button class="btn-sm primary" onclick="viewScript('01_Diagnostics/02_Compare_Plans_CE130_vs_CE160.sql')">Compare CE 130 vs 160</button>
      <button class="btn-sm" onclick="viewScript('05_Compatibility_CE_Controls/01_Database_Scoped_CE_and_Optimizer_Controls.sql')">DB-scoped CE controls</button>
      <button class="btn-sm" onclick="viewScript('05_Compatibility_CE_Controls/02_Query_Level_Hints_CheatSheet.sql')">Per-query hint cheat sheet</button>
      <button class="btn-sm" onclick="viewScript('04_Statistics_Indexes/01_Update_Statistics_PostMigration.sql')">Update statistics</button>
    </div>
    <pre style="margin-top:12px"><code>-- Database-wide (blunt) - keeps CL 160, forces the OLD CE 70 model everywhere:
ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = ON;

-- Narrower: single query only (no app change needed on SQL 2022 via Query Store hint)
SELECT ... OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));</code></pre>
  </div>

  <!-- ======================= DECISION GUIDE ======================= -->
  <div class="card-box">
    <h3>Which one, and in what order?</h3>
    <ol style="margin-left:18px;font-size:13px;line-height:1.75;color:var(--text-secondary)">
      <li><strong>Diagnose first.</strong> Confirm the layer: server config, blocking/waits, statistics, CE estimates, parameter sniffing, or IQP. Do not toggle blindly.</li>
      <li><strong>If regressed queries use scalar UDFs</strong> and plans show inlined logic &rarr; test <code>DISABLE_TSQL_SCALAR_UDF_INLINING</code> (per query first).</li>
      <li><strong>If the gap is in row estimates</strong> across many queries &rarr; test <code>FORCE_LEGACY_CARDINALITY_ESTIMATION</code> (per query first).</li>
      <li><strong>Narrow before broad.</strong> Query Store hint / statement hint &rarr; per-object &rarr; database-scoped configuration.</li>
      <li><strong>Both are bridges.</strong> Keep CL 160, stabilize, then fix root causes (stats, SARGability, UDF rewrites) and remove the toggle.</li>
    </ol>
    <div class="note-warn" style="margin-top:12px">
      <strong>Golden rule:</strong> These two switches keep you on CL 160 while you fix the real problem - they are not a destination.
      Reverting the whole database to CL 130 should be the <em>last</em> resort, not the first.
    </div>
  </div>
</div>

<div class="section-page" id="page-refs">
  <div class="page-header"><h2>References</h2><p>Official and community sources aligned with this playbook.</p></div>
  <div class="card-box">
    <ul class="ref-list">
      <li><a href="https://learn.microsoft.com/en-us/troubleshoot/sql/database-engine/install/windows/issues-upgrading-sql-server-2022" target="_blank" rel="noopener">Microsoft Learn  - Issues upgrading to SQL Server 2022</a></li>
      <li><a href="https://learn.microsoft.com/en-us/answers/questions/5776733/how-to-resolve-degraded-sql-performance-since-upgr" target="_blank" rel="noopener">Microsoft Q&A  - Degraded performance after 2016->2022 upgrade</a></li>
      <li><a href="https://techcommunity.microsoft.com/discussions/sql_server/compatibility-change-from-110-to-160-doubles-the-cpu/4405830" target="_blank" rel="noopener">Tech Community  - Compat 110->160 CPU doubling</a></li>
      <li><a href="https://www.brentozar.com/archive/2023/04/how-to-go-live-on-sql-server-2022/" target="_blank" rel="noopener">Brent Ozar  - How to go live on SQL Server 2022</a></li>
      <li><a href="https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-compatibility-level" target="_blank" rel="noopener">ALTER DATABASE compatibility level</a></li>
      <li><a href="https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store" target="_blank" rel="noopener">Query Store overview</a></li>
      <li><a href="https://learn.microsoft.com/en-us/sql/relational-databases/performance/query-store-hints" target="_blank" rel="noopener">Query Store hints (SQL 2022)</a></li>
      <li><a href="https://learn.microsoft.com/en-us/sql/sql-server/" target="_blank" rel="noopener">SQL Server documentation hub</a></li>
      <li><a href="https://www.sqlservercentral.com/forums/topic/upgrading-from-sql-server-2016-to-2022" target="_blank" rel="noopener">SQLServerCentral  - Upgrading 2016 to 2022</a></li>
    </ul>
  </div>
</div>

<div class="section-page" id="page-scripts">
  <div class="page-header">
    <h2>Script library</h2>
    <p>Embedded SQL  - view, copy, or download. Filter by tag or search by keyword.</p>
  </div>
  <div class="search-bar">
    <input type="search" id="scriptSearch" placeholder="Search scripts by name, tag, or keyword..." oninput="renderLibrary()" />
    <span id="scriptCount" style="font-size:12px;color:var(--text-secondary)"></span>
  </div>
  <div class="tag-filters" id="tagFilters"></div>
  <div class="card-box"><div id="scriptLibrary"></div></div>
</div>

</main>

<div class="script-viewer-overlay" id="scriptViewer" onclick="if(event.target===this)closeViewer()">
  <div class="script-viewer">
    <div class="script-viewer-header">
      <div>
        <strong id="viewerTitle">SQL Script</strong>
        <div class="viewer-meta" id="viewerMeta"></div>
      </div>
      <div>
        <button class="copy-btn accent" onclick="downloadCurrent()">Download .sql</button>
        <button class="copy-btn" onclick="copyScript()">Copy</button>
        <button class="copy-btn" onclick="closeViewer()">Close</button>
      </div>
    </div>
    <div class="script-viewer-body"><pre class="sql-code" id="viewerCode"></pre></div>
  </div>
</div>

<script>
'@

$html += "`n" + $scriptContentsJs + "`n`n" + $metaJs + "`n"

$html += @'

var currentScriptKey = null;
var activeTag = '';
var GUIDE_KEY = 'compat160_guided_step_v1';
var guideIndex = 0;

var guidedSteps = [
  {
    title: 'Confirm the symptom',
    why: 'You must prove slowness is tied to compatibility 160, not general server problems.',
    doList: [
      'Ask: Was the app fine at CL 130 on the new SQL 2022 server?',
      'Ask: Did slowness start only after SET COMPATIBILITY_LEVEL = 160?',
      'If slow even at CL 130 on the new host, this is mostly infra/config - not CE. Still run Steps 1-2, then escalate hardware/IO.',
      'If fine at 130 and slow at 160, continue this guide in order.'
    ],
    pass: 'You confirmed CL 160 is the trigger (or you know you must still fix baseline first).',
    fail: 'If the problem is unclear, gather app error times + one slow query text, then still continue to Step 2 for a baseline.',
    scripts: ['01_Diagnostics/01_Capture_Environment_Baseline.sql']
  },
  {
    title: 'Post-restore & instance baseline',
    why: 'A 2016 backup/restore carries stale stats and row counts. New hosts often keep CTFP=5 and wrong MAXDOP. Fix this before chasing CE.',
    doList: [
      'Prefer UAT/copy of the database.',
      'Run DBCC UPDATEUSAGE and plan FULLSCAN stats (maintenance window on large DBs).',
      'Set Cost Threshold for Parallelism to 30-50 (not 5).',
      'Set MAXDOP to physical cores per NUMA node (often 4-8 for OLTP).',
      'Enable optimize for ad hoc workloads = 1.',
      'Keep compatibility at 130 while doing this.'
    ],
    pass: 'Stats refreshed and instance settings look sane. App still slow only at CL 160 (or you have not flipped yet).',
    fail: 'If still slow at CL 130 after baseline, investigate IO/CPU/blocking first - do not jump to hints.',
    scripts: [
      '04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql',
      '02_Configuration/01_Recommended_Instance_Settings_2022.sql'
    ]
  },
  {
    title: 'Rule out blocking & engine waits',
    why: 'Juniors often blame the optimizer when the real issue is blocking, RESOURCE_SEMAPHORE, or storage waits.',
    doList: [
      'During a slow period, run the blocking chain collector.',
      'Check top waits and top CPU queries.',
      'If heavy LCK_* waits: fix blocking (long transactions) before CE work.',
      'If PAGEIOLATCH_* / WRITELOG dominate: storage/log - not CL 160 alone.'
    ],
    pass: 'No sustained blocking; waits do not fully explain the CL 160-only slowdown.',
    fail: 'Blocking or IO is the main story - resolve that, then re-test CL 160.',
    scripts: [
      '01_Diagnostics/09_Blocking_Chain_Collector.sql',
      '01_Diagnostics/03_Wait_Stats_and_Top_Queries.sql',
      '03_QueryStore_PlanForce/04_QueryStore_Wait_Statistics_Report.sql'
    ]
  },
  {
    title: 'Enable Query Store at CL 130',
    why: 'Without a baseline of good plans, you cannot prove regressions or force last-good plans safely.',
    doList: [
      'Enable Query Store (READ_WRITE) on the database.',
      'Enable WAIT_STATS_CAPTURE_MODE separately if SQL 2017+.',
      'Keep CL 130. Capture production/UAT workload for 3-7 days if possible (shorter in lab is OK).',
      'Capture a before metrics snapshot.'
    ],
    pass: 'Query Store is READ_WRITE and collecting. You have some history at CL 130.',
    fail: 'If QS will not stay online, fix storage/size settings first - do not flip CL 160 yet.',
    scripts: [
      '03_QueryStore_PlanForce/01_Enable_QueryStore.sql',
      '07_Monitoring_Baseline/01_Capture_Before_After_Metrics.sql'
    ]
  },
  {
    title: 'Flip CL 160 in UAT and find regressions',
    why: 'Never invent fixes. Measure which queries got worse after CL 160.',
    doList: [
      'On UAT only: ALTER DATABASE ... SET COMPATIBILITY_LEVEL = 160.',
      'ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE.',
      'Replay the same workload (or wait for natural load).',
      'Run the automatic regression report (duration, CPU, reads, waits).',
      'Note top query_id values that got 50%+ worse.'
    ],
    pass: 'You have a short list of regressed query_ids (or confirmed widespread regression).',
    fail: 'If nothing stands out in QS but app is slow, check blocking again and plan cache comparison.',
    scripts: [
      '03_QueryStore_PlanForce/05_Automatic_Regression_Report.sql',
      '03_QueryStore_PlanForce/02_Find_Regressed_Queries.sql',
      '01_Diagnostics/06_Plan_Cache_Comparison.sql',
      '05_Compatibility_CE_Controls/03_Compatibility_Level_Change_Runbook.sql'
    ]
  },
  {
    title: 'Validate statistics quality',
    why: 'Even after FULLSCAN, some columns may lack stats or have weak histograms that hurt CE 160 more than CE 130.',
    doList: [
      'Run statistics quality report on hot tables.',
      'Run missing statistics detector (ColumnsWithNoStatistics warnings).',
      'FULLSCAN any remaining critical offenders.',
      'Re-test the top regressed queries.'
    ],
    pass: 'Stats look healthy; regressions remain - continue to CE/IQP.',
    fail: 'If fixing stats resolved the app, stop here and document. Monitor.',
    scripts: [
      '04_Statistics_Indexes/03_Statistics_Quality_Report.sql',
      '04_Statistics_Indexes/04_Missing_Statistics_Detector.sql'
    ]
  },
  {
    title: 'Cardinality Estimator A/B test',
    why: 'Prove whether Legacy CE (2016-like) makes the slow query fast again.',
    doList: [
      'Take one top slow query.',
      'Run Compare Plans script: Legacy CE hint vs default CE.',
      'Check estimated vs actual rows, join type, spills, implicit conversions.',
      'If Legacy CE is clearly faster: CE regression confirmed for that query.'
    ],
    pass: 'You know if the issue is CE estimates, conversions, or something else.',
    fail: 'If Legacy CE does not help this query, go to sniffing / IQP next - do not enable whole-DB Legacy CE yet.',
    scripts: [
      '01_Diagnostics/02_Compare_Plans_CE130_vs_CE160.sql',
      '01_Diagnostics/04_Find_Implicit_Conversions_and_Warnings.sql',
      '01_Diagnostics/05_Find_IQP_and_CE_Plan_Fingerprints.sql'
    ]
  },
  {
    title: 'Parameter sniffing / PSP check',
    why: 'Same proc can be fast for one parameter and slow for another after CL 160.',
    doList: [
      'Run the parameter-sensitive query detector.',
      'In UAT, test OPTION (RECOMPILE) or OPTIMIZE FOR UNKNOWN on one suspect proc.',
      'If RECOMPILE fixes it: sniffing confirmed - plan a permanent approach (hint, rewrite, or PSP review).'
    ],
    pass: 'Sniffing ruled out, or you have a confirmed sniffing fix path.',
    fail: 'If not sniffing, continue to IQP isolation.',
    scripts: ['01_Diagnostics/07_Parameter_Sensitive_Query_Detector.sql']
  },
  {
    title: 'IQP isolation (one feature at a time)',
    why: '2016->2022 skips 2017/2019. UDF inlining, batch mode, and PSP turn on together and can each break plans.',
    doList: [
      'Check memory grants and spills.',
      'Read IQP skip-release notes.',
      'In UAT, disable ONE scoped setting, clear proc cache, retest (e.g. TSQL_SCALAR_UDF_INLINING = OFF).',
      'If that one feature fixes it: keep only that bridge; leave CL 160 ON.',
      'Never turn all IQP features OFF at once.'
    ],
    pass: 'You found the offending IQP feature, or none of them alone explain it.',
    fail: 'Continue to rewrites / surgical plan control.',
    scripts: [
      '01_Diagnostics/08_Memory_Grant_and_Spill_Analysis.sql',
      '05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql',
      '05_Compatibility_CE_Controls/05_IQP_Feature_Isolation_Toggles.sql'
    ]
  },
  {
    title: 'Fix the right way (branch: few vs many)',
    why: 'Hints and Legacy CE are tools - apply the smallest change that restores service, then plan permanent cleanup.',
    doList: [
      'FEW queries (1-15): Query Store force last good plan OR sp_query_store_set_hints (Legacy CE / RECOMPILE / disable UDF inline). No app deploy needed on SQL 2022.',
      'MANY queries: temporary LEGACY_CARDINALITY_ESTIMATION = ON and/or UDF inlining OFF; enable Automatic Tuning FORCE_LAST_GOOD_PLAN.',
      'Rewrite stubborn SQL (OR->UNION, MSTVF->iTVF, SARGable dates, temp tables).',
      'After stable: turn bridges OFF when permanent fixes exist.',
      'Production cutover only after UAT sign-off; keep rollback to CL 130 ready.'
    ],
    pass: 'UAT meets SLA at CL 160. Document forced plans / scoped configs / rewrites.',
    fail: 'If still failing after all steps: rollback UAT to CL 130, capture evidence, escalate with regression query_ids.',
    scripts: [
      '03_QueryStore_PlanForce/03_Force_Last_Good_Plan.sql',
      '05_Compatibility_CE_Controls/06_Automatic_Tuning_and_QueryStore_Hints.sql',
      '05_Compatibility_CE_Controls/01_Database_Scoped_CE_and_Optimizer_Controls.sql',
      '06_Code_Rewrite_Patterns/01_Before_After_Examples.sql',
      '07_Monitoring_Baseline/02_Post_Cutover_Health_Check.sql'
    ]
  }
];

var flowSteps = [
  { id:'postrestore', title:'1. Post-restore baseline', desc:'DBCC UPDATEUSAGE + stats FULLSCAN; CTFP 30-50, MAXDOP per NUMA, ad hoc ON. Do before CL 160.', keys:['04_Statistics_Indexes/05_Post_Restore_Maintenance_Before_CL160.sql','02_Configuration/01_Recommended_Instance_Settings_2022.sql'] },
  { id:'config', title:'2. Server / engine check', desc:'Confirm CU, memory, waits, blocking - rule out infra and locking.', keys:['01_Diagnostics/01_Capture_Environment_Baseline.sql','01_Diagnostics/09_Blocking_Chain_Collector.sql','01_Diagnostics/03_Wait_Stats_and_Top_Queries.sql'] },
  { id:'baseline', title:'3. Query Store at CL 130', desc:'Capture golden plans 3-7 days before flipping UAT/prod to 160.', keys:['03_QueryStore_PlanForce/01_Enable_QueryStore.sql','07_Monitoring_Baseline/01_Capture_Before_After_Metrics.sql'] },
  { id:'regression', title:'4. Flip CL 160 in UAT + regress report', desc:'Clear proc cache; compare duration, CPU, IO, waits before vs after.', keys:['03_QueryStore_PlanForce/05_Automatic_Regression_Report.sql','03_QueryStore_PlanForce/02_Find_Regressed_Queries.sql','01_Diagnostics/06_Plan_Cache_Comparison.sql'] },
  { id:'stats', title:'5. Statistics quality (if still suspect)', desc:'Histogram, sample rate, missing stats - before blaming CE alone.', keys:['04_Statistics_Indexes/03_Statistics_Quality_Report.sql','04_Statistics_Indexes/04_Missing_Statistics_Detector.sql'] },
  { id:'ce', title:'6. Cardinality Estimator', desc:'Plan compare, implicit conversions, Legacy CE A/B test.', keys:['01_Diagnostics/02_Compare_Plans_CE130_vs_CE160.sql','01_Diagnostics/04_Find_Implicit_Conversions_and_Warnings.sql','01_Diagnostics/05_Find_IQP_and_CE_Plan_Fingerprints.sql'] },
  { id:'sniffing', title:'7. Parameter sniffing / PSP', desc:'Multiple plans, runtime variance - test RECOMPILE in UAT.', keys:['01_Diagnostics/07_Parameter_Sensitive_Query_Detector.sql'] },
  { id:'iqp', title:'8. IQP (skipped 2017/2019 features)', desc:'UDF inlining, batch mode, MGF, CE/DOP feedback, PSP - isolate one feature.', keys:['05_Compatibility_CE_Controls/04_SQL2022_IQP_and_CE_Feedback_Notes.sql','01_Diagnostics/08_Memory_Grant_and_Spill_Analysis.sql','05_Compatibility_CE_Controls/05_IQP_Feature_Isolation_Toggles.sql'] },
  { id:'application', title:'9. Application / T-SQL patterns', desc:'OR, UDF->TVF, temp tables, SARGable predicates.', keys:['06_Code_Rewrite_Patterns/01_Before_After_Examples.sql'] },
  { id:'hints', title:'10. Hints & scoped bridges (last)', desc:'QS hints / plan force (few queries) OR Legacy CE / UDF inlining OFF (widespread).', keys:['05_Compatibility_CE_Controls/06_Automatic_Tuning_and_QueryStore_Hints.sql','05_Compatibility_CE_Controls/01_Database_Scoped_CE_and_Optimizer_Controls.sql','03_QueryStore_PlanForce/03_Force_Last_Good_Plan.sql'], last:true }
];

function toggleTheme(){
  var h=document.documentElement;
  h.setAttribute('data-theme', h.getAttribute('data-theme')==='dark'?'light':'dark');
}
function showPage(id){
  document.querySelectorAll('.section-page').forEach(function(p){ p.classList.remove('active'); });
  document.querySelectorAll('.sidebar-item').forEach(function(i){
    i.classList.toggle('active', i.getAttribute('data-page')===id);
  });
  var el=document.getElementById('page-'+id);
  if(el) el.classList.add('active');
  document.getElementById('sidebar').classList.remove('open');
  if(id==='flow') renderFlowchart();
  if(id==='scripts') { renderTagFilters(); renderLibrary(); }
  if(id==='guided') renderGuided();
}
function loadGuideIndex(){
  var v=parseInt(localStorage.getItem(GUIDE_KEY)||'0',10);
  if(isNaN(v)||v<0) v=0;
  if(v>guidedSteps.length) v=guidedSteps.length;
  guideIndex=v;
}
function saveGuideIndex(){ localStorage.setItem(GUIDE_KEY, String(guideIndex)); }
function resetGuided(){
  if(!confirm('Reset guided progress to Step 1?')) return;
  guideIndex=0;
  saveGuideIndex();
  renderGuided();
}
function goGuideStep(i){
  if(i<0) i=0;
  if(i>guidedSteps.length) i=guidedSteps.length;
  // Only allow going to current or earlier completed steps (synchronous order)
  if(i>guideIndex) {
    alert('Follow the steps in order. Finish the current step first, then click: Did not help - go to next step.');
    return;
  }
  // When navigating history, show that step but keep guideIndex as furthest
  renderGuidedAt(i);
}
function guideResolved(){
  guideIndex=guidedSteps.length;
  saveGuideIndex();
  renderGuided();
}
function guideNext(){
  if(guideIndex < guidedSteps.length){
    guideIndex++;
    saveGuideIndex();
  }
  renderGuided();
}
function renderGuided(){
  loadGuideIndex();
  var view = Math.min(guideIndex, guidedSteps.length-1);
  if(guideIndex >= guidedSteps.length) {
    renderGuidedDone();
    return;
  }
  renderGuidedAt(view);
}
function renderGuidedDone(){
  var list=document.getElementById('guideStepList');
  var panel=document.getElementById('guidePanel');
  var done=document.getElementById('guideDoneBox');
  var bar=document.getElementById('guideProgressBar');
  var lab=document.getElementById('guideProgressLabel');
  if(bar) bar.style.width='100%';
  if(lab) lab.textContent='Complete - issue marked resolved';
  if(list){
    list.innerHTML=guidedSteps.map(function(s,i){
      return '<li class="done" onclick="goGuideStep('+i+')"><span class="gnum">'+(i+1)+'</span><span>'+s.title+'</span></li>';
    }).join('');
  }
  if(panel) panel.style.display='none';
  if(done) done.classList.add('show');
}
function renderGuidedAt(viewIdx){
  var list=document.getElementById('guideStepList');
  var panel=document.getElementById('guidePanel');
  var done=document.getElementById('guideDoneBox');
  var bar=document.getElementById('guideProgressBar');
  var lab=document.getElementById('guideProgressLabel');
  if(done) done.classList.remove('show');
  if(panel) panel.style.display='block';
  var pct = Math.round((guideIndex / guidedSteps.length) * 100);
  if(bar) bar.style.width=pct+'%';
  if(lab) lab.textContent='Step '+(viewIdx+1)+' of '+guidedSteps.length+' (furthest reached: '+(Math.min(guideIndex+1,guidedSteps.length))+')';

  if(list){
    list.innerHTML=guidedSteps.map(function(s,i){
      var cls = i===viewIdx ? 'active' : (i<guideIndex ? 'done' : '');
      return '<li class="'+cls+'" onclick="goGuideStep('+i+')"><span class="gnum">'+(i+1)+'</span><span>'+s.title+'</span></li>';
    }).join('');
  }

  var s=guidedSteps[viewIdx];
  if(!s||!panel) return;
  var html='';
  html+='<div class="badge badge-ver">Step '+(viewIdx+1)+' of '+guidedSteps.length+'</div>';
  html+='<h3 style="margin-top:8px">'+s.title+'</h3>';
  html+='<div class="guide-why"><strong>Why this step:</strong> '+s.why+'</div>';
  html+='<div class="guide-do"><strong>What to do:</strong><ol style="margin:6px 0 0 18px">';
  s.doList.forEach(function(d){ html+='<li style="margin:4px 0">'+d+'</li>'; });
  html+='</ol></div>';
  html+='<div class="guide-pass"><strong>Pass (move on only if true):</strong> '+s.pass+'</div>';
  html+='<div class="guide-fail"><strong>If it did not help:</strong> '+s.fail+'</div>';
  html+='<div style="margin-top:12px"><strong style="font-size:13px">Scripts for this step:</strong><div class="guide-actions">';
  (s.scripts||[]).forEach(function(k){
    var name=k.split('/').pop();
    html+='<button class="btn-sm primary" onclick="viewScript(\''+k+'\')">'+name+'</button>';
  });
  html+='</div></div>';

  html+='<div class="guide-actions" style="margin-top:18px;padding-top:14px;border-top:1px solid var(--border)">';
  if(viewIdx === guideIndex){
    html+='<button class="btn-sm btn-success" onclick="guideResolved()">This fixed the issue - stop here</button>';
    if(guideIndex < guidedSteps.length-1){
      html+='<button class="btn-sm btn-next" onclick="guideNext()">Did not help - go to next step</button>';
    } else {
      html+='<button class="btn-sm btn-next" onclick="guideNext()">Finished all steps</button>';
    }
  } else if(viewIdx < guideIndex){
    html+='<button class="btn-sm primary" onclick="renderGuidedAt(guideIndex)">Return to current step</button>';
  }
  html+='</div>';
  panel.innerHTML=html;
}
function safetyClass(s){
  if(s==='Safe') return 'badge-safe';
  if(s==='High Risk') return 'badge-risk';
  return 'badge-test';
}
function getMeta(key){ return scriptMeta.find(function(m){ return m.key===key; }); }
function viewScript(file){
  currentScriptKey=file;
  var m=getMeta(file);
  document.getElementById('viewerTitle').textContent=file;
  var body=scriptContents[file]||('-- Not found: '+file);
  document.getElementById('viewerCode').textContent=body;
  var metaHtml='';
  if(m){
    metaHtml+='<span class="badge '+safetyClass(m.safety)+'">'+m.safety+'</span> ';
    metaHtml+='<span class="badge badge-ver">'+m.execTime+'</span> ';
    (m.versions||[]).forEach(function(v){ metaHtml+='<span class="badge badge-ver">'+v+'</span> '; });
    metaHtml+='<br><strong>Dependencies:</strong> '+(m.deps||[]).join(' | ');
    metaHtml+='<br><strong>Tags:</strong> '+(m.tags||[]).join(', ');
    metaHtml+='<br><strong>Package path:</strong> <code>'+file+'</code> (relative to this HTML)';
  }
  document.getElementById('viewerMeta').innerHTML=metaHtml;
  document.getElementById('scriptViewer').classList.add('active');
}
function closeViewer(){ document.getElementById('scriptViewer').classList.remove('active'); }
function copyScript(){
  var t=document.getElementById('viewerCode').textContent;
  if(navigator.clipboard) navigator.clipboard.writeText(t);
}
function downloadScript(file){
  var body=scriptContents[file];
  if(!body) return;
  var a=document.createElement('a');
  a.href=URL.createObjectURL(new Blob([body],{type:'application/sql;charset=utf-8'}));
  a.download=file.split('/').pop();
  a.click();
}
function downloadCurrent(){ if(currentScriptKey) downloadScript(currentScriptKey); }
function allTags(){
  var t={};
  scriptMeta.forEach(function(m){ (m.tags||[]).forEach(function(x){ t[x]=1; }); });
  return Object.keys(t).sort();
}
function renderTagFilters(){
  var root=document.getElementById('tagFilters');
  if(!root||root.dataset.done) return;
  root.dataset.done='1';
  var html='<button class="tag-btn active" data-tag="" onclick="setTag(\'\')">All</button>';
  allTags().forEach(function(tag){
    html+='<button class="tag-btn" data-tag="'+tag+'" onclick="setTag(\''+tag+'\')">'+tag+'</button>';
  });
  root.innerHTML=html;
}
function setTag(tag){
  activeTag=tag;
  document.querySelectorAll('.tag-btn').forEach(function(b){
    b.classList.toggle('active', b.getAttribute('data-tag')===tag);
  });
  renderLibrary();
}
function filteredMeta(){
  var q=(document.getElementById('scriptSearch')||{}).value||'';
  q=q.toLowerCase();
  return scriptMeta.filter(function(m){
    if(activeTag && (m.tags||[]).indexOf(activeTag)<0) return false;
    if(!q) return true;
    var blob=(m.key+' '+m.title+' '+(m.tags||[]).join(' ')+(m.deps||[]).join(' ')).toLowerCase();
    return blob.indexOf(q)>=0;
  });
}
function renderLibrary(){
  var root=document.getElementById('scriptLibrary');
  var countEl=document.getElementById('scriptCount');
  if(!root) return;
  var items=filteredMeta();
  if(countEl) countEl.textContent=items.length+' script(s)';
  var cats=[];
  items.forEach(function(m){ if(cats.indexOf(m.cat)<0) cats.push(m.cat); });
  var html='';
  cats.forEach(function(cat){
    html+='<div class="cat-header">'+cat+'</div>';
    items.filter(function(m){return m.cat===cat;}).forEach(function(m){
      html+='<div class="script-row">';
      html+='<div><span class="script-name" onclick="viewScript(\''+m.key+'\')">'+m.key.split('/').pop()+'</span>';
      html+='<div class="script-meta-line">';
      html+='<span class="badge '+safetyClass(m.safety)+'">'+m.safety+'</span>';
      html+='<span class="badge badge-ver">'+m.execTime+'</span>';
      (m.versions||[]).forEach(function(v){ html+='<span class="badge badge-ver">'+v+'</span>'; });
      (m.tags||[]).slice(0,4).forEach(function(t){ html+='<span class="badge badge-tag">'+t+'</span>'; });
      html+='</div></div>';
      html+='<div><div>'+m.title+'</div><div class="deps">'+((m.deps||[]).join(' | '))+'</div></div>';
      html+='<div><button class="btn-sm primary" onclick="viewScript(\''+m.key+'\')">View</button> ';
      html+='<button class="btn-sm" onclick="downloadScript(\''+m.key+'\')">Download</button> ';
      html+='<a class="btn-sm" href="'+m.key+'" download="'+m.key.split('/').pop()+'" title="Open loose .sql from package folder">Open file</a></div>';
      html+='</div>';
    });
  });
  root.innerHTML=html||'<p style="color:var(--text-secondary)">No scripts match.</p>';
}
function renderFlowchart(){
  var root=document.getElementById('flowchart');
  if(!root) return;
  var html='';
  flowSteps.forEach(function(step, i){
    html+='<div class="flow-node'+(step.last?' last-resort':'')+'" onclick="openFlowStep(\''+step.id+'\')">';
    html+='<h4>'+step.title+'</h4><p>'+step.desc+'</p>';
    html+='<p style="margin-top:6px;font-size:10px;color:var(--accent)">'+(step.keys.length)+' script(s)  - click to open first</p>';
    html+='</div>';
    if(i<flowSteps.length-1) html+='<div class="flow-arrow">&#8595;</div>';
  });
  root.innerHTML=html;
}
function openFlowStep(id){
  var step=flowSteps.find(function(s){ return s.id===id; });
  if(step && step.keys.length) viewScript(step.keys[0]);
}
document.documentElement.setAttribute('data-theme','light');
document.addEventListener('keydown', function(e){ if(e.key==='Escape') closeViewer(); });
renderFlowchart();
renderTagFilters();
renderLibrary();
loadGuideIndex();
</script>
</body>
</html>
'@

[System.IO.File]::WriteAllText($outPath, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "Built $outPath ($([math]::Round((Get-Item $outPath).Length/1KB,1)) KB, $($manifest.Count) scripts)"
