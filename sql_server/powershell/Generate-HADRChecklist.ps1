param(
    [ValidateRange(1,3)][int]$SecondaryReplicas = 1,
    [ValidateSet('FileShare','Cloud','Disk','None')][string]$WitnessType = 'FileShare',
    [ValidateRange(1,2)][int]$DomainControllerCount = 1,
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot '..') (Join-Path 'output' 'HADR_Checklist.html')),
    [switch]$IncludeReadableSecondary,
    [switch]$IncludeBackupOnSecondary,
    [switch]$Interactive
)

# =====================================================================
# Interactive mode
# =====================================================================
if (-not $Interactive -and $PSBoundParameters.Count -eq 0) {
    $Interactive = $true
}

if ($Interactive) {
    Clear-Host
    Write-Host "==================================================================================" -ForegroundColor Cyan
    Write-Host "               HADR CHECKLIST GENERATOR - INTERACTIVE SETUP" -ForegroundColor Yellow
    Write-Host "==================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script generates an interactive HTML checklist for SQL Server Always On"
    Write-Host "Availability Groups setup. Answer the questions below to customize your checklist."
    Write-Host ""
    Write-Host "----------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    # --- Secondary Replicas ---
    $currentReplicas = $SecondaryReplicas
    Write-Host ">> STEP 1: Number of Secondary Replicas" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Determines how many SQL Server replicas will be included in the AG."
    Write-Host "  Each extra replica adds more redundancy but also more setup steps."
    Write-Host ""
    Write-Host "  [1] 1 secondary replica  $( if ($currentReplicas -eq 1) { '<<< CURRENT' } else { '' } )" -ForegroundColor $(if ($currentReplicas -eq 1) { 'Yellow' } else { 'White' })
    Write-Host "      Nodes: SQL01 (primary), SQL02 (synchronous commit)"
    Write-Host "      Best for: Basic HA with automatic failover, zero data loss"
    Write-Host ""
    Write-Host "  [2] 2 secondary replicas $( if ($currentReplicas -eq 2) { '<<< CURRENT' } else { '' } )" -ForegroundColor $(if ($currentReplicas -eq 2) { 'Yellow' } else { 'White' })
    Write-Host "      Nodes: SQL01 (primary), SQL02 (sync), SQL03 (async)"
    Write-Host "      Best for: Multi-site HA with local sync + DR replica"
    Write-Host ""
    Write-Host "  [3] 3 secondary replicas ($( if ($currentReplicas -eq 3) { '<< CURRENT' } else { 'Maximum availability' } ))" -ForegroundColor $(if ($currentReplicas -eq 3) { 'Yellow' } else { 'White' })
    Write-Host "      Nodes: SQL01 (primary), SQL02 (sync), SQL03 (async), SQL04 (async)"
    Write-Host "      Best for: Distributed AG with multiple DR sites"
    Write-Host ""
    $resp = Read-Host "Enter choice [1-$($currentReplicas)]"
    if ([string]::IsNullOrWhiteSpace($resp)) { $resp = "$currentReplicas" }
    $SecondaryReplicas = [Math]::Max(1, [Math]::Min(3, [int]$resp))
    Write-Host ""

    # --- Witness Type ---
    $currentWitness = $WitnessType
    Write-Host ">> STEP 2: Cluster Witness Type" -ForegroundColor Green
    Write-Host ""
    Write-Host "  The witness provides a tie-breaking vote for cluster quorum."
    Write-Host "  Without a witness, a 2-node cluster can lose quorum if one node fails."
    Write-Host ""
    Write-Host "  [1] FileShare  ($( if ($currentWitness -eq 'FileShare') { '<< CURRENT' } else { 'Uses a file server' } ))" -ForegroundColor $(if ($currentWitness -eq 'FileShare') { 'Yellow' } else { 'White' })
    Write-Host "      Creates a file share on DC01 as witness."
    Write-Host "      Pro: Simple, no extra cost. Con: Needs a file server."
    Write-Host ""
    Write-Host "  [2] Cloud      ($( if ($currentWitness -eq 'Cloud') { '<< CURRENT' } else { 'Uses Azure blob storage' } ))" -ForegroundColor $(if ($currentWitness -eq 'Cloud') { 'Yellow' } else { 'White' })
    Write-Host "      Uses Azure Storage account as witness."
    Write-Host "      Pro: Highly available, no on-prem dependency. Con: Needs Azure subscription."
    Write-Host ""
    Write-Host "  [3] Disk       ($( if ($currentWitness -eq 'Disk') { '<< CURRENT' } else { 'Uses shared SAN storage' } ))" -ForegroundColor $(if ($currentWitness -eq 'Disk') { 'Yellow' } else { 'White' })
    Write-Host "      Uses a small LUN from shared SAN storage."
    Write-Host "      Pro: Automatic failover. Con: Requires shared storage (SAN)."
    Write-Host ""
    Write-Host "  [4] None       ($( if ($currentWitness -eq 'None') { '<< CURRENT' } else { 'No witness (3+ nodes only)' } ))" -ForegroundColor $(if ($currentWitness -eq 'None') { 'Yellow' } else { 'White' })
    Write-Host "      No witness. Only recommended with 3+ cluster nodes."
    Write-Host "      Pro: Simple. Con: Risk of split-brain with even number of nodes."
    Write-Host ""
    $resp = Read-Host "Enter choice [1-4]"
    $WitnessType = switch ([string]$resp) { '2' { 'Cloud' } '3' { 'Disk' } '4' { 'None' } default { 'FileShare' } }
    Write-Host ""

    # --- Domain Controller Count ---
    $currentDCs = $DomainControllerCount
    Write-Host ">> STEP 3: Domain Controller Count" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Determines how many Domain Controllers are set up."
    Write-Host "  A second DC provides redundancy for AD and DNS services."
    Write-Host ""
    Write-Host "  [1] 1 DC  ($( if ($currentDCs -eq 1) { '<< CURRENT' } else { 'Single domain controller' } ))" -ForegroundColor $(if ($currentDCs -eq 1) { 'Yellow' } else { 'White' })
    Write-Host "      Single point of failure. If DC01 goes down, authentication stops."
    Write-Host "      Adequate for: Labs, dev/test environments."
    Write-Host ""
    Write-Host "  [2] 2 DCs ($( if ($currentDCs -eq 2) { '<< CURRENT' } else { 'Redundant domain controllers' } ))" -ForegroundColor $(if ($currentDCs -eq 2) { 'Yellow' } else { 'White' })
    Write-Host "      Adds DC02 with AD replication and DNS redundancy."
    Write-Host "      Adequate for: Production environments, critical workloads."
    Write-Host ""
    $resp = Read-Host "Enter choice [1-$($currentDCs)]"
    if ([string]::IsNullOrWhiteSpace($resp)) { $resp = "$currentDCs" }
    $DomainControllerCount = [Math]::Max(1, [Math]::Min(2, [int]$resp))
    Write-Host ""

    # --- Readable Secondary ---
    Write-Host ">> STEP 4: Readable Secondary Replicas" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Allows read-only queries on secondary replicas."
    Write-Host "  Useful for offloading reporting workloads from the primary."
    Write-Host ""
    Write-Host "  [Y] Yes  ($( if ($IncludeReadableSecondary) { '<< CURRENT' } else { 'Allow read-only access' } ))" -ForegroundColor $(if ($IncludeReadableSecondary) { 'Yellow' } else { 'White' })
    Write-Host "      Adds read-only routing configuration steps."
    Write-Host "      Pro: Offloads reporting queries. Con: Slightly more complex setup."
    Write-Host ""
    Write-Host "  [N] No   ($( if (-not $IncludeReadableSecondary) { '<< CURRENT' } else { 'Read-only not needed' } ))" -ForegroundColor $(if (-not $IncludeReadableSecondary) { 'Yellow' } else { 'White' })
    Write-Host "      Simpler setup. Secondaries accept no connections."
    Write-Host "      Pro: Fewer steps. Con: Cannot use secondary for reporting."
    Write-Host ""
    $resp = Read-Host "Enter choice [y/N]"
    $IncludeReadableSecondary = $resp -eq 'Y' -or $resp -eq 'y'
    Write-Host ""

    # --- Summary ---
    Clear-Host
    Write-Host "==================================================================================" -ForegroundColor Cyan
    Write-Host "                      CONFIGURATION SUMMARY" -ForegroundColor Yellow
    Write-Host "==================================================================================" -ForegroundColor Cyan
    Write-Host ""
    $totalReplicas = $SecondaryReplicas + 1
    Write-Host "  Secondary Replicas : $SecondaryReplicas (total nodes: $totalReplicas)" -ForegroundColor White
    Write-Host "  Witness Type       : $WitnessType" -ForegroundColor White
    Write-Host "  Domain Controllers : $DomainControllerCount" -ForegroundColor White
    Write-Host "  Readable Secondary : $(if ($IncludeReadableSecondary) { 'Yes' } else { 'No' })" -ForegroundColor White
    Write-Host "  Output File        : $OutputPath" -ForegroundColor White
    Write-Host ""
    Write-Host "  Estimated checklist steps will vary based on these selections." -ForegroundColor DarkGray
    Write-Host "  More replicas, DCs, and features = more detailed checklist steps." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "----------------------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    $proceed = Read-Host "Generate the checklist? [Y/n]"
    if ($proceed -eq 'n' -or $proceed -eq 'N') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 0
    }
    Write-Host ""
    Write-Host "Generating checklist..." -ForegroundColor Yellow
    Write-Host ""
}

$steps = @()

$dcNames = @('DC01')
if ($DomainControllerCount -ge 2) { $dcNames += 'DC02' }

$sqlNodeNames = @('SQL01')
for ($i = 1; $i -le $SecondaryReplicas; $i++) {
    $sqlNodeNames += "SQL0$($i+1)"
}
$primaryNode = $sqlNodeNames[0]
$secondaryNodes = $sqlNodeNames[1..$($sqlNodeNames.Count-1)]
$totalNodes = $sqlNodeNames.Count

$ipMapping = @{}
$ipMapping['DC01'] = '10.10.10.10'
if ($DomainControllerCount -ge 2) { $ipMapping['DC02'] = '10.10.10.11' }
$ipMapping['SQL01'] = '10.10.10.20'
for ($i = 1; $i -le $SecondaryReplicas; $i++) {
    $ipMapping["SQL0$($i+1)"] = "10.10.10.$($i+20)"
}
$clusterIP = '10.10.10.30'
$listenerIP = '10.10.10.31'
$subnet = '255.255.255.0'
$gateway = '10.10.10.1'
$domain = 'corp.local'
$domainNetbios = 'CORP'
$agName = 'AG_PROD'
$listenerName = 'SQLPROD-LSN'
$clusterName = 'SQLCLUSTER'

switch ($WitnessType) {
    'FileShare' { $witnessPath = '\\DC01\ClusterWitness'; $witnessDesc = 'File Share Witness'; $witnessSteps = 5 }
    'Cloud'     { $witnessPath = 'cloud witness'; $witnessDesc = 'Cloud Witness'; $witnessSteps = 5 }
    'Disk'      { $witnessPath = 'disk witness'; $witnessDesc = 'Disk Witness'; $witnessSteps = 5 }
    'None'      { $witnessPath = 'none'; $witnessDesc = 'No Witness'; $witnessSteps = 3 }
}

function Add-Step {
    param(
        [string]$PhaseID,
        [string]$PhaseName,
        [string]$StepID,
        [string]$Task,
        [string]$Details,
        [string]$Command,
        [string]$ExpectedResult,
        [string]$WhyThisMatters,
        [string]$Prerequisite,
        [int]$EstMinutes = 5,
        [string]$VerificationMethod = "Visual verification",
        [ValidateSet('Required','Recommended','Optional')][string]$Severity = 'Required'
    )
    $script:steps += [PSCustomObject]@{
        PhaseID          = $PhaseID
        PhaseName        = $PhaseName
        StepID           = $StepID
        Category         = ""
        Task             = $Task
        Details          = $Details
        Command          = $Command
        ExpectedResult   = $ExpectedResult
        WhyThisMatters   = $WhyThisMatters
        Prerequisite     = $Prerequisite
        EstMinutes       = $EstMinutes
        Status           = "Not Started"
        CompletedBy      = ""
        CompletedDate    = ""
        VerifiedBy       = ""
        VerificationDate = ""
        VerificationMethod = $VerificationMethod
        Severity         = $Severity
        Notes            = ""
    }
}

# ======================================================================
# PHASE 1: Infrastructure Planning
# ======================================================================
$p = "Phase 1"; $pn = "Infrastructure Planning"
Add-Step -PhaseID $p -PhaseName $pn -StepID "1.1" -Task "Identify project stakeholders and responsibilities" `
    -Details "List all team members involved (DBA, SysAdmin, Network Admin, Security, App Team). Assign a primary contact for each area." `
    -Command "Create a contact list with names, roles, email, phone" `
    -ExpectedResult "Contact list documented and shared with team" `
    -WhyThisMatters "HADR setup involves multiple teams. Having clear ownership prevents delays" `
    -Prerequisite "None" -EstMinutes 15 -VerificationMethod "Document review"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.2" -Task "Document all application connection strings" `
    -Details "Find all applications connecting to SQL Server. Note connection strings, especially any hardcoded server names. List all databases and their sizes." `
    -Command "Check app config files, web.config, connectionstrings.config" `
    -ExpectedResult "Complete inventory of applications, database sizes, and connection patterns" `
    -WhyThisMatters "After AG setup, apps must connect to the Listener name, not the server name" `
    -Prerequisite "1.1" -EstMinutes 30 -VerificationMethod "Signed off by app team lead"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.3" -Task "Plan IP addressing scheme" `
    -Details "Document all IP addresses needed for: $($dcNames -join ', '), $($sqlNodeNames -join ', '), Cluster IP ($clusterIP), Listener IP ($listenerIP). Reserve them in DHCP or plan static assignment." `
    -Command "Create IP allocation table with server name, IP, subnet mask, gateway, DNS" `
    -ExpectedResult "IP address plan documented and IPs reserved in network team's system" `
    -WhyThisMatters "IP conflicts cause outages. Static IPs required for cluster nodes" `
    -Prerequisite "1.1" -EstMinutes 15 -VerificationMethod "IP plan signed off by network team"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.4" -Task "Plan domain and DNS naming" `
    -Details "Active Directory domain: $domain. Hostnames: $($dcNames -join ', '), $($sqlNodeNames -join ', '). Listener: $listenerName. Cluster: $clusterName." `
    -Command "Document planned names in a table" `
    -ExpectedResult "Naming convention documented and approved" `
    -WhyThisMatters "Domain name and hostnames must be unique. Listener name is the connection point" `
    -Prerequisite "1.1" -EstMinutes 10 -VerificationMethod "Document review"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.5" -Task "Plan service accounts with least privilege" `
    -Details "Plan AD accounts: svc_sql (SQL Service), svc_sqlagent (SQL Agent), svc_cluster (Cluster). Consider using gMSA for production." `
    -Command "List accounts: $domainNetbios\svc_sql, $domainNetbios\svc_sqlagent, $domainNetbios\svc_cluster" `
    -ExpectedResult "Service account list documented with purposes and required permissions" `
    -WhyThisMatters "Service accounts run SQL Server and Cluster. Separate accounts follow least-privilege" `
    -Prerequisite "1.1" -EstMinutes 15 -VerificationMethod "Document review by security team"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.6" -Task "Plan drive layout and storage configuration" `
    -Details "Document drive letters: C:\ (OS 100GB), D:\ (Data), L:\ (Log), B:\ (Backup), T:\ (TempDB). Ensure all drives are NTFS." `
    -Command "On existing servers: Get-PSDrive -PSProvider FileSystem | Select Name, Used, Free" `
    -ExpectedResult "Drive layout documented with expected sizes. Verify adequate free space." `
    -WhyThisMatters "Separating data, logs, TempDB, backups prevents I/O contention. Log drives on fast storage" `
    -Prerequisite "None" -EstMinutes 15 -VerificationMethod "Compare plan with actual available storage"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.7" -Task "Verify Windows Server edition and version compatibility" `
    -Details "Check Windows edition and build across all $totalNodes SQL nodes." `
    -Command "(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName; (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild" `
    -ExpectedResult "All servers show same Windows edition and build number" `
    -WhyThisMatters "Mixed Windows versions can cause cluster compatibility issues" `
    -Prerequisite "None" -EstMinutes 10 -VerificationMethod "Compare output from all servers"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.8" -Task "Verify SQL Server edition and version compatibility" `
    -Details "All SQL nodes must have same major version, same edition (Enterprise), and same patch level." `
    -Command "SELECT @@VERSION; SERVERPROPERTY('Edition'); SERVERPROPERTY('ProductLevel'); SERVERPROPERTY('ProductUpdateLevel')" `
    -ExpectedResult "All nodes report identical SQL version, edition, and patch level" `
    -WhyThisMatters "AG requires identical versions on all replicas. Even CU differences can break sync" `
    -Prerequisite "None" -EstMinutes 10 -VerificationMethod "Compare @@VERSION output from all servers"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.9" -Task "Verify SQL Server collation is identical on all nodes" `
    -Details "Check server-level collation on all SQL instances. They MUST match." `
    -Command "SELECT SERVERPROPERTY('Collation')" `
    -ExpectedResult "All servers return the same collation name" `
    -WhyThisMatters "Different collations prevent AG creation. Cannot change collation without reinstall" `
    -Prerequisite "None" -EstMinutes 5 -VerificationMethod "Compare output from all servers"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.10" -Task "Assess network bandwidth between sites" `
    -Details "If replicas span datacenters, measure latency and bandwidth between sites. AG requires low-latency connections (sub-10ms recommended for synchronous commit)." `
    -Command "Test-NetConnection <remote-node> -Port 5022; ping <remote-node> -n 20" `
    -ExpectedResult "Latency and bandwidth documented. Latency under 10ms for synchronous commit" `
    -WhyThisMatters "High latency impacts AG synchronization. Async commit may be needed for high-latency links" `
    -Prerequisite "1.3" -EstMinutes 20 -VerificationMethod "Latency report generated"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.11" -Task "Create project timeline and rollback plan" `
    -Details "Create step-by-step timeline with estimated durations. Document rollback steps for each phase. Schedule maintenance window." `
    -Command "Create a Gantt chart or timeline document" `
    -ExpectedResult "Project plan with timeline, milestones, and rollback procedures approved" `
    -WhyThisMatters "HADR setup impacts production. Rollback plan is your safety net" `
    -Prerequisite "1.1" -EstMinutes 30 -VerificationMethod "Signed off by project manager"

Add-Step -PhaseID $p -PhaseName $pn -StepID "1.12" -Task "Configure sp_configure baseline settings per best practices" `
    -Details "Review and set SQL Server sp_configure settings: max degree of parallelism, cost threshold for parallelism, max server memory, optimize for ad hoc workloads, backup compression default." `
    -Command "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'max degree of parallelism', 0; EXEC sp_configure 'cost threshold for parallelism', 50; EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;" `
    -ExpectedResult "sp_configure values documented and applied to match best practices" `
    -WhyThisMatters "Proper baseline settings ensure consistent performance across all replicas after failover" `
    -Prerequisite "1.8" -EstMinutes 15 -VerificationMethod "EXEC sp_configure; verify settings match baseline document"

# ======================================================================
# PHASE 2: Domain Controller Setup
# ======================================================================
$p = "Phase 2"; $pn = "Domain Controller Setup"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.1" -Task "Log into DC01 as local administrator" `
    -Details "RDP or console to DC01. Log in with local administrator account created during Windows installation." `
    -Command "mstsc /v:DC01" `
    -ExpectedResult "Logged into DC01 with administrative access" `
    -WhyThisMatters "Domain setup requires local admin rights" `
    -Prerequisite "1.3, 1.4" -EstMinutes 2 -VerificationMethod "Verify admin access"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.2" -Task "Assign static IP address to DC01" `
    -Details "Set static IP: $($ipMapping['DC01']), Subnet: $subnet, Gateway: $gateway, DNS: 127.0.0.1" `
    -Command "New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '$($ipMapping['DC01'])' -PrefixLength 24 -DefaultGateway '$gateway'; Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '127.0.0.1'" `
    -ExpectedResult "DC01 has static IP $($ipMapping['DC01']), DNS set to 127.0.0.1" `
    -WhyThisMatters "DCs must use static IPs. Clients rely on DC being at a fixed address" `
    -Prerequisite "2.1" -EstMinutes 5 -VerificationMethod "ipconfig /all confirms IP and DNS"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.3" -Task "Rename DC01 to match naming convention" `
    -Details "Set hostname to DC01. Restart when prompted." `
    -Command "Rename-Computer -NewName 'DC01' -Restart" `
    -ExpectedResult "Server reboots with hostname DC01" `
    -WhyThisMatters "Consistent hostnames help with identification" `
    -Prerequisite "2.2" -EstMinutes 5 -VerificationMethod "hostname returns 'DC01'"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.4" -Task "Install Active Directory Domain Services role" `
    -Details "Install AD DS role with management tools." `
    -Command "Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools" `
    -ExpectedResult "Installation success message. No reboot required yet." `
    -WhyThisMatters "AD DS is the foundation of Active Directory. Without AD, domain join fails" `
    -Prerequisite "2.3" -EstMinutes 10 -VerificationMethod "Get-WindowsFeature AD-Domain-Services shows Installed"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.5" -Task "Install DNS Server role" `
    -Details "Install DNS Server role. DNS is required for AD to function." `
    -Command "Install-WindowsFeature -Name DNS -IncludeManagementTools" `
    -ExpectedResult "DNS Server role installed successfully" `
    -WhyThisMatters "DNS is critical for AD. Domain controllers register services in DNS" `
    -Prerequisite "2.4" -EstMinutes 5 -VerificationMethod "Get-WindowsFeature DNS shows Installed"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.6" -Task "Promote server to Domain Controller" `
    -Details "Promote to domain controller in new forest. Domain: $domain" `
    -Command "Install-ADDSForest -DomainName '$domain' -InstallDNS -DomainMode WinThreshold -ForestMode WinThreshold -Force" `
    -ExpectedResult "Server reboots after promotion. Log in with $domainNetbios\Administrator" `
    -WhyThisMatters "Promotion creates the AD forest. This is the central authentication authority" `
    -Prerequisite "2.4, 2.5" -EstMinutes 20 -VerificationMethod "Run whoami to confirm domain context"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.7" -Task "Verify AD DS and DNS services are running" `
    -Details "Check core AD services: NTDS, DNS, KDC, NetLogon all Running." `
    -Command "Get-Service NTDS, DNS, KDC, NetLogon | Select Name, Status" `
    -ExpectedResult "All four services show Status: Running" `
    -WhyThisMatters "These services provide authentication, directory lookups, and name resolution" `
    -Prerequisite "2.6" -EstMinutes 5 -VerificationMethod "Get-Service shows all Running"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.8" -Task "Configure DNS forwarders for external resolution" `
    -Details "Add 8.8.8.8 and 1.1.1.1 as forwarders for external name resolution." `
    -Command "Add-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1" `
    -ExpectedResult "DNS forwarders configured. nslookup google.com resolves" `
    -WhyThisMatters "Needed for Windows Update, license activation, and downloading patches" `
    -Prerequisite "2.7" -EstMinutes 5 -VerificationMethod "nslookup google.com returns IP"

Add-Step -PhaseID $p -PhaseName $pn -StepID "2.9" -Task "Create reverse lookup zone for subnet" `
    -Details "Create PTR reverse lookup zone for IP-to-hostname resolution." `
    -Command "Add-DnsServerPrimaryZone -NetworkID '10.10.10.0/24' -ReplicationScope Forest" `
    -ExpectedResult "Reverse lookup zone created in DNS" `
    -WhyThisMatters "Reverse lookup helps troubleshooting by showing hostnames instead of IPs in logs" `
    -Prerequisite "2.7" -EstMinutes 5 -VerificationMethod "nslookup $($ipMapping['DC01']) returns DC01.$domain"

if ($DomainControllerCount -ge 2) {
    Add-Step -PhaseID $p -PhaseName $pn -StepID "2.10" -Task "Log into DC02 and configure static IP" `
        -Details "Set DC02 static IP: $($ipMapping['DC02']), Subnet: $subnet, Gateway: $gateway, DNS: $($ipMapping['DC01'])" `
        -Command "New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '$($ipMapping['DC02'])' -PrefixLength 24 -DefaultGateway '$gateway'; Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '$($ipMapping['DC01'])'" `
        -ExpectedResult "DC02 has static IP $($ipMapping['DC02'])" `
        -WhyThisMatters "Second DC provides AD redundancy. Must point DNS to DC01 for domain join" `
        -Prerequisite "2.7" -EstMinutes 5 -VerificationMethod "ipconfig confirms IP"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "2.11" -Task "Rename DC02" `
        -Details "Set hostname to DC02 and restart." `
        -Command "Rename-Computer -NewName 'DC02' -Restart" `
        -ExpectedResult "Server reboots with hostname DC02" `
        -WhyThisMatters "Consistent naming for identification" `
        -Prerequisite "2.10" -EstMinutes 5 -VerificationMethod "hostname returns 'DC02'"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "2.12" -Task "Install AD DS and DNS roles on DC02" `
        -Details "Install AD DS and DNS roles on DC02." `
        -Command "Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools" `
        -ExpectedResult "Roles installed successfully" `
        -WhyThisMatters "Second DC needs AD DS to host a replica of the domain database" `
        -Prerequisite "2.11" -EstMinutes 10 -VerificationMethod "Get-WindowsFeature shows Installed"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "2.13" -Task "Promote DC02 to replica Domain Controller" `
        -Details "Add DC02 as an additional domain controller in the existing $domain domain." `
        -Command "Install-ADDSDomainController -DomainName '$domain' -InstallDNS -Credential (Get-Credential '$domainNetbios\Administrator') -Force" `
        -ExpectedResult "DC02 promotes and reboots. It becomes a replica DC" `
        -WhyThisMatters "Second DC provides AD high availability. If DC01 fails, DC02 continues authentication" `
        -Prerequisite "2.12" -EstMinutes 20 -VerificationMethod "Get-ADDomainController shows both DCs"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "2.14" -Task "Verify AD replication between DCs" `
        -Details "Check that AD replication is working between DC01 and DC02." `
        -Command "Get-ADReplicationPartnerMetadata -Target 'DC01' -Partition '*' | Format-List Partner, LastReplicationAttempt, LastReplicationResult; repadmin /replsummary" `
        -ExpectedResult "Replication showing successful attempts with no errors" `
        -WhyThisMatters "AD replication must work for consistent authentication across all servers" `
        -Prerequisite "2.13" -EstMinutes 10 -VerificationMethod "repadmin /replsummary shows 0 failures"
}

# ======================================================================
# PHASE 3: Service Accounts & Security Groups
# ======================================================================
$p = "Phase 3"; $pn = "Service Accounts & Security Groups"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.1" -Task "Open Active Directory Users and Computers" `
    -Details "Open ADUC to manage users, groups, and OUs." `
    -Command "dsa.msc" `
    -ExpectedResult "ADUC console opens showing $domain structure" `
    -WhyThisMatters "ADUC is the management console for AD objects" `
    -Prerequisite "2.6" -EstMinutes 2 -VerificationMethod "Console opens"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.2" -Task "Create Organizational Units for better management" `
    -Details "Create: _ServiceAccounts, _Servers, _Groups, _Users OUs under $domain." `
    -Command "New-ADOrganizationalUnit -Name '_ServiceAccounts' -Path 'DC=corp,DC=local'; New-ADOrganizationalUnit -Name '_Servers' -Path 'DC=corp,DC=local'; New-ADOrganizationalUnit -Name '_Groups' -Path 'DC=corp,DC=local'; New-ADOrganizationalUnit -Name '_Users' -Path 'DC=corp,DC=local'" `
    -ExpectedResult "Four new OUs appear under $domain" `
    -WhyThisMatters "OUs allow selective Group Policy application and cleaner AD navigation" `
    -Prerequisite "3.1" -EstMinutes 5 -VerificationMethod "OUs visible in ADUC tree"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.3" -Task "Create SQL Service account (svc_sql)" `
    -Details "Create svc_sql in _ServiceAccounts OU. Strong password, never expires." `
    -Command "New-ADUser -Name 'svc_sql' -SamAccountName 'svc_sql' -UserPrincipalName 'svc_sql@$domain' -Path 'OU=_ServiceAccounts,DC=corp,DC=local' -AccountPassword (Read-Host 'Enter password' -AsSecureString) -Enabled `$true -PasswordNeverExpires `$true" `
    -ExpectedResult "User svc_sql created in _ServiceAccounts OU" `
    -WhyThisMatters "svc_sql runs the SQL Server database engine. Separate account for security isolation" `
    -Prerequisite "3.2" -EstMinutes 5 -VerificationMethod "Get-ADUser svc_sql shows the account"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.4" -Task "Create SQL Agent service account (svc_sqlagent)" `
    -Details "Create svc_sqlagent in _ServiceAccounts OU. Strong password, never expires." `
    -Command "New-ADUser -Name 'svc_sqlagent' -SamAccountName 'svc_sqlagent' -UserPrincipalName 'svc_sqlagent@$domain' -Path 'OU=_ServiceAccounts,DC=corp,DC=local' -AccountPassword (Read-Host 'Enter password' -AsSecureString) -Enabled `$true -PasswordNeverExpires `$true" `
    -ExpectedResult "User svc_sqlagent created" `
    -WhyThisMatters "Separating SQL Engine and Agent accounts follows least-privilege principle" `
    -Prerequisite "3.2" -EstMinutes 5 -VerificationMethod "Get-ADUser svc_sqlagent shows the account"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.5" -Task "Create Cluster service account (svc_cluster)" `
    -Details "Create svc_cluster in _ServiceAccounts OU. Strong password, never expires." `
    -Command "New-ADUser -Name 'svc_cluster' -SamAccountName 'svc_cluster' -UserPrincipalName 'svc_cluster@$domain' -Path 'OU=_ServiceAccounts,DC=corp,DC=local' -AccountPassword (Read-Host 'Enter password' -AsSecureString) -Enabled `$true -PasswordNeverExpires `$true" `
    -ExpectedResult "User svc_cluster created" `
    -WhyThisMatters "Cluster service needs a domain account to communicate with other nodes" `
    -Prerequisite "3.2" -EstMinutes 5 -VerificationMethod "Get-ADUser svc_cluster shows the account"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.6" -Task "Pre-stage cluster Computer Object (CNO) in AD" `
    -Details "Create computer account ${clusterName}$ in _Servers OU. Grant svc_cluster Full Control." `
    -Command "New-ADComputer -Name '$clusterName' -Path 'OU=_Servers,DC=corp,DC=local' -Enabled `$false; dsacls 'CN=$clusterName,OU=_Servers,DC=corp,DC=local' /G '$domainNetbios\svc_cluster:CCDC;Computer' /I:T" `
    -ExpectedResult "Computer account $clusterName created but disabled. svc_cluster has permissions." `
    -WhyThisMatters "Pre-staging CNO ensures cluster can create identity without Domain Admin rights" `
    -Prerequisite "3.5" -EstMinutes 10 -VerificationMethod "Get-ADComputer $clusterName shows the object"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.7" -Task "Delegate control to svc_cluster for computer objects" `
    -Details "Delegate create/manage computer objects permission on _Servers OU to svc_cluster." `
    -Command "dsacls 'OU=_Servers,DC=corp,DC=local' /G '$domainNetbios\svc_cluster:CCDC;Computer' /I:T" `
    -ExpectedResult "svc_cluster has delegated control on _Servers OU" `
    -WhyThisMatters "Needed for AG listener Virtual Computer Object creation in AD" `
    -Prerequisite "3.6" -EstMinutes 5 -VerificationMethod "Test delegation using dsacls"

Add-Step -PhaseID $p -PhaseName $pn -StepID "3.8" -Task "Create SQL Administrators security group" `
    -Details "Create domain security group SQL_Admins for centralized SQL Server permission management." `
    -Command "New-ADGroup -Name 'SQL_Admins' -GroupScope Global -GroupCategory Security -Path 'OU=_Groups,DC=corp,DC=local'" `
    -ExpectedResult "SQL_Admins security group created" `
    -WhyThisMatters "Centralized group simplifies adding DBAs to SQL Server without per-server management" `
    -Prerequisite "3.2" -EstMinutes 5 -VerificationMethod "Get-ADGroup SQL_Admins shows the group"

# ======================================================================
# PHASE 4: DNS Configuration
# ======================================================================
$p = "Phase 4"; $pn = "DNS Configuration"

Add-Step -PhaseID $p -PhaseName $pn -StepID "4.1" -Task "Verify forward lookup zone for $domain exists" `
    -Details "Check that forward lookup zone exists and has SOA/NS records." `
    -Command "Get-DnsServerZone -Name '$domain' | Format-List ZoneName, ZoneType, IsAutoCreated" `
    -ExpectedResult "Forward lookup zone $domain exists with type Primary" `
    -WhyThisMatters "Forward lookup resolves hostnames to IPs for domain resolution" `
    -Prerequisite "2.6" -EstMinutes 3 -VerificationMethod "DNS Manager shows zone $domain"

foreach ($node in $dcNames) {
    Add-Step -PhaseID $p -PhaseName $pn -StepID "4.2.$node" -Task "Create A record for $node" `
        -Details "Create A record: $node -> $($ipMapping[$node])" `
        -Command "Add-DnsServerResourceRecordA -Name '$node' -ZoneName '$domain' -IPv4Address '$($ipMapping[$node])' -CreatePtr" `
        -ExpectedResult "nslookup $node returns $($ipMapping[$node])" `
        -WhyThisMatters "A records map hostnames to IPs for all servers on the network" `
        -Prerequisite "4.1" -EstMinutes 2 -VerificationMethod "nslookup confirms resolution"
}

foreach ($node in $sqlNodeNames) {
    Add-Step -PhaseID $p -PhaseName $pn -StepID "4.3.$node" -Task "Create A record for $node" `
        -Details "Create A record: $node -> $($ipMapping[$node])" `
        -Command "Add-DnsServerResourceRecordA -Name '$node' -ZoneName '$domain' -IPv4Address '$($ipMapping[$node])' -CreatePtr" `
        -ExpectedResult "nslookup $node returns $($ipMapping[$node])" `
        -WhyThisMatters "Pre-creating DNS records ensures immediate resolution after domain join" `
        -Prerequisite "4.1" -EstMinutes 2 -VerificationMethod "nslookup confirms resolution"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "4.4" -Task "Create A record for AG Listener ($listenerName)" `
    -Details "Create A record: $listenerName -> $listenerIP" `
    -Command "Add-DnsServerResourceRecordA -Name '$listenerName' -ZoneName '$domain' -IPv4Address '$listenerIP' -CreatePtr" `
    -ExpectedResult "nslookup $listenerName returns $listenerIP" `
    -WhyThisMatters "Listener DNS record enables applications to connect via a constant name" `
    -Prerequisite "4.1" -EstMinutes 2 -VerificationMethod "nslookup confirms resolution"

Add-Step -PhaseID $p -PhaseName $pn -StepID "4.5" -Task "Create A record for Cluster ($clusterName)" `
    -Details "Create A record: $clusterName -> $clusterIP" `
    -Command "Add-DnsServerResourceRecordA -Name '$clusterName' -ZoneName '$domain' -IPv4Address '$clusterIP' -CreatePtr" `
    -ExpectedResult "nslookup $clusterName returns $clusterIP" `
    -WhyThisMatters "WSFC cluster needs a DNS record for management and internal communications" `
    -Prerequisite "4.1" -EstMinutes 2 -VerificationMethod "nslookup confirms resolution"

Add-Step -PhaseID $p -PhaseName $pn -StepID "4.6" -Task "Enable dynamic DNS updates and set scavenging" `
    -Details "Configure secure dynamic updates and enable scavenging with 7-day interval." `
    -Command "Set-DnsServerScavenging -ApplyOnZones '$domain' -ScavengingState `$true -ScavengingInterval 7.00:00:00; Set-DnsServerPrimaryZone -Name '$domain' -DynamicUpdate Secure" `
    -ExpectedResult "Zone configured for secure dynamic updates and scavenging enabled" `
    -WhyThisMatters "Dynamic updates allow domain-joined computers to register their own DNS records" `
    -Prerequisite "4.1" -EstMinutes 5 -VerificationMethod "Check zone properties in DNS Manager"

Add-Step -PhaseID $p -PhaseName $pn -StepID "4.7" -Task "Verify all DNS records resolve correctly" `
    -Details "Test resolution of all server names and the listener from multiple machines." `
    -Command "nslookup DC01.$domain; nslookup SQL01.$domain; nslookup $listenerName.$domain; nslookup $clusterName.$domain" `
    -ExpectedResult "All names resolve to correct IPs" `
    -WhyThisMatters "DNS is critical for all cluster and AG operations. Verify before proceeding" `
    -Prerequisite "4.6" -EstMinutes 5 -VerificationMethod "All nslookup tests pass"

# ======================================================================
# PHASE 5: Network Configuration on SQL Servers
# ======================================================================
$p = "Phase 5"; $pn = "Network Configuration on SQL Servers"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "5.$idx.1" -Task "Log into $node as local administrator" `
        -Details "RDP or console into $node using local administrator account." `
        -Command "mstsc /v:$node" `
        -ExpectedResult "Logged into $node with local admin access" `
        -WhyThisMatters "Network configuration requires administrative privileges" `
        -Prerequisite "4.7" -EstMinutes 2 -VerificationMethod "Admin access confirmed"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "5.$idx.2" -Task "Configure static IP on $node" `
        -Details "Set IP: $($ipMapping[$node]), Subnet: $subnet, Gateway: $gateway, DNS: $($ipMapping['DC01'])" `
        -Command "New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress '$($ipMapping[$node])' -PrefixLength 24 -DefaultGateway '$gateway'; Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses '$($ipMapping['DC01'])'" `
        -ExpectedResult "$node has static IP $($ipMapping[$node]) with DNS pointing to DC01" `
        -WhyThisMatters "Static IP ensures the server address never changes. Cluster nodes MUST have static IPs" `
        -Prerequisite "5.$idx.1" -EstMinutes 5 -VerificationMethod "ipconfig shows correct IP and DNS"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "5.$idx.3" -Task "Rename $node if needed" `
        -Details "Set hostname to $node and reboot." `
        -Command "Rename-Computer -NewName '$node' -Restart" `
        -ExpectedResult "Server reboots with hostname $node" `
        -WhyThisMatters "Server name becomes part of the AG configuration" `
        -Prerequisite "5.$idx.2" -EstMinutes 5 -VerificationMethod "hostname returns '$node'"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "5.$idx.4" -Task "Optimize network adapter settings" `
        -Details "Disable TCP Chimney Offload, RSS, and VMQ on cluster network adapters. Set adapter speed/duplex to match switch configuration." `
        -Command "Disable-NetAdapterRSS -Name 'Ethernet'; netsh int tcp set global chimney=disabled; netsh int tcp set global rss=disabled" `
        -ExpectedResult "TCP offload features disabled. Network adapter optimized for cluster traffic" `
        -WhyThisMatters "TCP offload features can cause network issues in WSFC environments. Disabling improves stability" `
        -Prerequisite "5.$idx.3" -EstMinutes 5 -VerificationMethod "netsh int tcp show global confirms settings"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "5.1.5" -Task "Test network connectivity between all servers" `
    -Details "From each SQL server, ping all other servers by hostname and IP." `
    -Command "$(foreach ($n in $sqlNodeNames) { "Test-NetConnection $n -Port 445; " })$(foreach ($n in $dcNames) { "Test-NetConnection $n -Port 445; " })ping $($sqlNodeNames[0]); ping $($sqlNodeNames[-1])" `
    -ExpectedResult "All pings succeed. nslookup returns correct IPs" `
    -WhyThisMatters "Network connectivity is the foundation. If servers can't communicate, everything fails" `
    -Prerequisite "5.$($totalNodes).3" -EstMinutes 10 -VerificationMethod "All ping and nslookup tests pass"

Add-Step -PhaseID $p -PhaseName $pn -StepID "5.1.6" -Task "Disable IPv6 on cluster/AG network adapters" `
    -Details "Uncheck IPv6 on network adapters to prevent IPv6 from interfering with WSFC and AG." `
    -Command "Get-NetAdapterBinding -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -ComponentID ms_tcpip6" `
    -ExpectedResult "IPv6 disabled on network adapter. Reboot required." `
    -WhyThisMatters "WSFC/AG are primarily IPv4-based. Both stacks can cause resolution issues" `
    -Prerequisite "5.1.5" -EstMinutes 5 -VerificationMethod "ipconfig shows no IPv6 address"

Add-Step -PhaseID $p -PhaseName $pn -StepID "5.1.7" -Task "Configure Windows Firewall to allow ICMP for troubleshooting" `
    -Details "Enable ICMPv4 inbound rule to allow ping through firewall." `
    -Command "New-NetFirewallRule -DisplayName 'Allow ICMPv4' -Protocol ICMPv4 -Direction Inbound -Action Allow" `
    -ExpectedResult "ICMP echo requests allowed through firewall" `
    -WhyThisMatters "Ping is the first troubleshooting tool for connectivity issues" `
    -Prerequisite "5.1.5" -EstMinutes 3 -VerificationMethod "From DC01, ping SQL01 succeeds"

Add-Step -PhaseID $p -PhaseName $pn -StepID "5.1.8" -Task "Enable jumbo frames on cluster network" `
    -Details "Set MTU to 9000 on cluster network adapters if switch infrastructure supports jumbo frames." `
    -Command "Set-NetAdapterAdvancedProperty -Name 'Ethernet' -DisplayName 'Jumbo Packet' -DisplayValue '9014'" `
    -ExpectedResult "Jumbo frames enabled on network adapter" `
    -WhyThisMatters "Jumbo frames reduce CPU overhead and improve large data transfer performance for AG sync" `
    -Prerequisite "5.1.5" -EstMinutes 5 -VerificationMethod "Get-NetAdapterAdvancedProperty confirms setting" `
    -Severity Recommended

# ======================================================================
# PHASE 6: Join SQL Servers to Domain
# ======================================================================
$p = "Phase 6"; $pn = "Join SQL Servers to Domain"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "6.$idx.1" -Task "Join $node to $domain domain" `
        -Details "Join $node to $domain. Provide domain admin credentials when prompted. Reboot after join." `
        -Command "Add-Computer -DomainName '$domain' -Credential $domainNetbios\Administrator -Restart -Force" `
        -ExpectedResult "$node reboots and you can log in with $domainNetbios\Administrator" `
        -WhyThisMatters "Domain join enables centralized authentication, Group Policy, and WSFC clustering" `
        -Prerequisite "5.$idx.3" -EstMinutes 10 -VerificationMethod "systeminfo shows Domain: $domain"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "6.$idx.2" -Task "Add domain admins to local Administrators group on $node" `
        -Details "Add $domainNetbios\Domain Admins and $domainNetbios\svc_cluster to local Administrators group." `
        -Command "Add-LocalGroupMember -Group 'Administrators' -Member '$domainNetbios\Domain Admins', '$domainNetbios\svc_cluster' -ErrorAction SilentlyContinue" `
        -ExpectedResult "Domain Admins and svc_cluster are members of local Administrators group" `
        -WhyThisMatters "Domain Admins need local admin rights to install software. svc_cluster needs rights for cluster management" `
        -Prerequisite "6.$idx.1" -EstMinutes 5 -VerificationMethod "Get-LocalGroupMember Administrators shows new members"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "6.1.3" -Task "Verify domain membership on all SQL nodes" `
    -Details "Log in with domain account on each SQL server. Confirm domain membership." `
    -Command "systeminfo | Select-String 'Domain'; (Get-WmiObject Win32_ComputerSystem).Domain" `
    -ExpectedResult "All servers report Domain: $domain" `
    -WhyThisMatters "Double-check prevents the common mistake of a server remaining in a workgroup" `
    -Prerequisite "6.$($totalNodes).2" -EstMinutes 3 -VerificationMethod "All servers show $domain"

Add-Step -PhaseID $p -PhaseName $pn -StepID "6.1.4" -Task "Verify DNS registration after domain join" `
    -Details "Confirm all SQL nodes registered their A records in DNS after domain join." `
    -Command "Get-DnsServerResourceRecord -ZoneName '$domain' -RRType A | Where-Object { `$_.HostName -like 'SQL*' }" `
    -ExpectedResult "All SQL servers have A records in DNS" `
    -WhyThisMatters "DNS registration is critical for cluster name resolution" `
    -Prerequisite "6.1.3" -EstMinutes 5 -VerificationMethod "DNS records visible in DNS Manager"

# ======================================================================
# PHASE 7: SQL Server Installation
# ======================================================================
$p = "Phase 7"; $pn = "SQL Server Installation"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    $isFirstNode = ($node -eq $primaryNode)

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.1" -Task "Download SQL Server installation media on $node" `
        -Details "Download SQL Server Enterprise edition from Visual Studio Subscriptions or VLSC. Mount the ISO." `
        -Command "Mount-DiskImage -ImagePath 'C:\Setup\SQL2022_Enterprise.iso'" `
        -ExpectedResult "ISO mounted as a virtual DVD drive" `
        -WhyThisMatters "You need the installation files. Enterprise edition required for AG with readable secondary" `
        -Prerequisite "6.$idx.1" -EstMinutes 10 -VerificationMethod "ISO mounted and visible"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.2" -Task "Launch SQL Server Installation Center on $node" `
        -Details "Run setup.exe from mounted ISO. Select 'New SQL Server stand-alone installation'." `
        -Command "D:\setup.exe (where D: is the mounted ISO drive)" `
        -ExpectedResult "SQL Server Installation Center opens" `
        -WhyThisMatters "This is the starting point for SQL Server installation" `
        -Prerequisite "7.$idx.1" -EstMinutes 2 -VerificationMethod "Installation wizard appears"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.3" -Task "Enter product key and accept license terms on $node" `
        -Details "Enter your SQL Server product key. Accept license terms." `
        -Command "Enter product key for SQL Server Enterprise" `
        -ExpectedResult "Product key accepted, license terms agreed" `
        -WhyThisMatters "Without valid key, SQL Server installs as Evaluation edition with 180-day limit" `
        -Prerequisite "7.$idx.2" -EstMinutes 2 -VerificationMethod "Wizard proceeds past product key screen"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.4" -Task "Select SQL Server features on $node" `
        -Details "Select: Database Engine Services, SQL Server Replication, Full-Text Search, Client Tools Connectivity, Management Tools." `
        -Command "Select features in wizard" `
        -ExpectedResult "Required features selected" `
        -WhyThisMatters "Database Engine is core. Management Tools gives SSMS. Only install what you need" `
        -Prerequisite "7.$idx.3" -EstMinutes 3 -VerificationMethod "Features list visible on next screen"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.5" -Task "Configure SQL Server instance on $node" `
        -Details "Keep Default instance. Default instance uses port 1433." `
        -Command "Select Default instance" `
        -ExpectedResult "Default instance selected" `
        -WhyThisMatters "Default instance is simpler for AG. Named instances require additional port config" `
        -Prerequisite "7.$idx.4" -EstMinutes 2 -VerificationMethod "Instance page shows MSSQLSERVER"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.6" -Task "Configure SQL Server Service Accounts on $node" `
        -Details "Set SQL Engine service to $domainNetbios\svc_sql. Set SQL Agent to $domainNetbios\svc_sqlagent. Startup Types: Automatic." `
        -Command "SQL Engine -> $domainNetbios\svc_sql; SQL Agent -> $domainNetbios\svc_sqlagent" `
        -ExpectedResult "Service accounts configured and credentials accepted" `
        -WhyThisMatters "Domain accounts allow SQL to authenticate to domain resources (backup shares, linked servers)" `
        -Prerequisite "3.3, 3.4, 7.$idx.5" -EstMinutes 5 -VerificationMethod "Wizard accepts credentials"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.7" -Task "Configure Collation on $node" `
        -Details "Ensure collation matches between all nodes. Default: SQL_Latin1_General_CP1_CI_AS" `
        -Command "Default collation: SQL_Latin1_General_CP1_CI_AS" `
        -ExpectedResult "Collation configured and matches between all servers" `
        -WhyThisMatters "Different collations prevent AG creation. Cannot change without rebuilding master DB" `
        -Prerequisite "1.9, 7.$idx.6" -EstMinutes 2 -VerificationMethod "Collation confirmed in wizard"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.8" -Task "Configure Authentication Mode on $node" `
        -Details "Select Mixed Mode. Set strong sa password. Add CORP\Administrator, CORP\svc_sql, CORP\svc_cluster as SQL admins." `
        -Command "Mixed Mode; add $domainNetbios\Administrator, $domainNetbios\svc_sql, $domainNetbios\svc_cluster" `
        -ExpectedResult "Mixed mode enabled, admin accounts added" `
        -WhyThisMatters "Mixed Mode required for AG setup scripts and SQL auth applications" `
        -Prerequisite "7.$idx.7" -EstMinutes 5 -VerificationMethod "Admins listed on configuration page"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.9" -Task "Configure Data Directories on $node" `
        -Details "Set paths: Data Root -> D:\MSSQL\Data, Log -> L:\MSSQL\Log, Backup -> B:\MSSQL\Backup, TempDB -> T:\MSSQL\TempDB" `
        -Command "Set paths to D:\MSSQL\Data, L:\MSSQL\Log, B:\MSSQL\Backup, T:\MSSQL\TempDB" `
        -ExpectedResult "Data directories configured on separate drives" `
        -WhyThisMatters "Separating data, logs, TempDB, backups prevents I/O contention" `
        -Prerequisite "1.6, 7.$idx.8" -EstMinutes 3 -VerificationMethod "Paths correctly set in wizard"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.10" -Task "Configure TempDB on $node" `
        -Details "Set initial size 1024 MB per file, autogrowth 512 MB. Number of files = CPU cores (max 8)." `
        -Command "TempDB: Initial 1024MB, Autogrowth 512MB, Count = CPU cores (max 8)" `
        -ExpectedResult "TempDB configured optimally" `
        -WhyThisMatters "Multiple TempDB files reduce allocation contention. Proper sizing prevents space exhaustion" `
        -Prerequisite "7.$idx.9" -EstMinutes 3 -VerificationMethod "TempDB settings reflected in wizard"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.11" -Task "Complete SQL Server installation on $node" `
        -Details "Review settings and click Install. Installation takes 15-30 minutes." `
        -Command "Click Install and wait for completion" `
        -ExpectedResult "SQL Server installed successfully. Feature results show 'Success'" `
        -WhyThisMatters "This installs SQL Server with all configured settings" `
        -Prerequisite "7.$idx.10" -EstMinutes 30 -VerificationMethod "Installation complete page shows all features succeeded"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "7.$idx.12" -Task "Install latest SQL Server Cumulative Update on $node" `
        -Details "Download and apply the latest CU. Both/all nodes must be patched to the same level." `
        -Command "Run the CU installer on $node" `
        -ExpectedResult "SQL Server updated to latest CU on $node" `
        -WhyThisMatters "CU contains bug fixes and security patches. All nodes must be at same patch level" `
        -Prerequisite "7.$idx.11" -EstMinutes 20 -VerificationMethod "SELECT @@VERSION shows updated build"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "7.1.13" -Task "Verify SQL Server services on all nodes" `
    -Details "Confirm MSSQLSERVER, SQLSERVERAGENT, SQLBrowser are Running with Automatic start on all nodes." `
    -Command "Get-Service MSSQLSERVER, SQLSERVERAGENT, SQLBrowser | Format-Table Name, Status, StartType" `
    -ExpectedResult "All services show Status: Running, StartType: Automatic on all nodes" `
    -WhyThisMatters "SQL must be running for DB operations. Agent schedules backups and monitoring" `
    -Prerequisite "7.$($totalNodes).12" -EstMinutes 5 -VerificationMethod "Services Running on all servers"

Add-Step -PhaseID $p -PhaseName $pn -StepID "7.1.14" -Task "Configure SQL Server SP_CONFIGURE baselines" `
    -Details "Set baseline sp_configure settings: max degree of parallelism, cost threshold, max memory, optimize for ad hoc workloads." `
    -Command "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'max degree of parallelism', 0; EXEC sp_configure 'cost threshold for parallelism', 50; EXEC sp_configure 'optimize for ad hoc workloads', 1; RECONFIGURE;" `
    -ExpectedResult "sp_configure values set to best practice defaults on all nodes" `
    -WhyThisMatters "Consistent baseline settings ensure predictable performance after failover" `
    -Prerequisite "7.1.13" -EstMinutes 10 -VerificationMethod "EXEC sp_configure; verify settings match baseline"

Add-Step -PhaseID $p -PhaseName $pn -StepID "7.1.15" -Task "Perform post-installation health checks" `
    -Details "Check SQL error log for errors. Verify SQL Agent is running. Verify default trace is enabled. Check disk space on data/log/backup drives." `
    -Command "EXEC sp_readerrorlog 0; EXEC xp_fixeddrives; SELECT name, is_default FROM sys.traces WHERE is_default = 1" `
    -ExpectedResult "No critical errors in SQL log. Sufficient disk space. Default trace enabled." `
    -WhyThisMatters "Post-installation checks catch configuration issues before they cause problems" `
    -Prerequisite "7.1.14" -EstMinutes 10 -VerificationMethod "Error log reviewed and documented"

# ======================================================================
# PHASE 8: Enable Always On Availability Groups
# ======================================================================
$p = "Phase 8"; $pn = "Enable Always On Availability Groups"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "8.$idx.1" -Task "Open SQL Server Configuration Manager on $node" `
        -Details "Open SQL Server Configuration Manager (SQLServerManager16.msc)." `
        -Command "SQLServerManager16.msc" `
        -ExpectedResult "Configuration Manager opens" `
        -WhyThisMatters "Configuration Manager manages SQL Server service settings including Always On" `
        -Prerequisite "7.1.13" -EstMinutes 1 -VerificationMethod "Config Manager window opens"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "8.$idx.2" -Task "Enable Always On on $node" `
        -Details "Right-click SQL Server (MSSQLSERVER) -> Properties -> Always On HA tab -> Check 'Enable Always On Availability Groups'." `
        -Command "Enable Always On in SQL Server Configuration Manager" `
        -ExpectedResult "Always On feature enabled. Restart message shown." `
        -WhyThisMatters "Enables AG feature in SQL Server. Without this, AG options are unavailable" `
        -Prerequisite "8.$idx.1" -EstMinutes 2 -VerificationMethod "Checkbox checked in properties"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "8.$idx.3" -Task "Restart SQL Server service on $node" `
        -Details "Restart SQL Server service to apply the Always On setting." `
        -Command "Restart-Service MSSQLSERVER" `
        -ExpectedResult "SQL Server service restarts and shows Running" `
        -WhyThisMatters "Always On setting requires a service restart to take effect" `
        -Prerequisite "8.$idx.2" -EstMinutes 5 -VerificationMethod "Get-Service MSSQLSERVER shows Running"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "8.$idx.4" -Task "Verify Always On is enabled via T-SQL on $node" `
        -Details "Query SERVERPROPERTY to confirm Always On is active." `
        -Command "SELECT SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled;" `
        -ExpectedResult "Returns 1 (Always On is enabled)" `
        -WhyThisMatters "SERVERPROPERTY('IsHadrEnabled') = 1 is the definitive check" `
        -Prerequisite "8.$idx.3" -EstMinutes 2 -VerificationMethod "Query returns 1"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "8.1.5" -Task "Verify Always On enabled on ALL nodes" `
    -Details "Confirm all SQL nodes have IsHadrEnabled = 1" `
    -Command "SELECT @@SERVERNAME AS ServerName, SERVERPROPERTY('IsHadrEnabled') AS IsHadrEnabled;" `
    -ExpectedResult "All nodes return 1" `
    -WhyThisMatters "Every replica must have Always On enabled to participate in the AG" `
    -Prerequisite "8.$($totalNodes).4" -EstMinutes 3 -VerificationMethod "All nodes show IsHadrEnabled = 1"

# ======================================================================
# PHASE 9: Install Windows Server Failover Cluster Feature
# ======================================================================
$p = "Phase 9"; $pn = "Install Windows Server Failover Cluster (WSFC) Feature"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "9.$idx.1" -Task "Install Failover Clustering feature on $node" `
        -Details "Install Failover Clustering feature with management tools." `
        -Command "Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools" `
        -ExpectedResult "Failover Clustering installed on $node" `
        -WhyThisMatters "WSFC is the underlying clustering technology that AG relies on" `
        -Prerequisite "6.$idx.1" -EstMinutes 5 -VerificationMethod "Get-WindowsFeature shows Installed"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "9.$idx.2" -Task "Verify WSFC installation on $node" `
        -Details "Confirm Failover Clustering is installed." `
        -Command "Get-WindowsFeature -Name Failover-Clustering | Select-Object Name, Installed" `
        -ExpectedResult "Installed = True" `
        -WhyThisMatters "All cluster nodes must have WSFC feature installed to participate" `
        -Prerequisite "9.$idx.1" -EstMinutes 2 -VerificationMethod "Shows Installed"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "9.1.3" -Task "Verify WSFC on ALL nodes" `
    -Details "Confirm Failover Clustering installed on every SQL node." `
    -Command "Get-WindowsFeature -Name Failover-Clustering | Select-Object Name, Installed" `
    -ExpectedResult "Installed = True on all servers" `
    -WhyThisMatters "If one node lacks WSFC, cluster creation fails" `
    -Prerequisite "9.$($totalNodes).2" -EstMinutes 2 -VerificationMethod "All nodes show Installed"

# ======================================================================
# PHASE 10: Validate Cluster Configuration
# ======================================================================
$p = "Phase 10"; $pn = "Validate Cluster Configuration"

$validateNodes = "($($sqlNodeNames -join ', '))"
Add-Step -PhaseID $p -PhaseName $pn -StepID "10.1" -Task "Run cluster validation tests" `
    -Details "Run Test-Cluster with all SQL nodes. Comprehensive test of network, storage, system config." `
    -Command "Test-Cluster -Node $($sqlNodeNames -join ', ') -ReportFilePath 'C:\Temp\ClusterValidation.html' -Include 'Inventory', 'Network', 'System Configuration'" `
    -ExpectedResult "Validation tests run and generate HTML report" `
    -WhyThisMatters "Validation catches configuration issues BEFORE creating the cluster" `
    -Prerequisite "9.1.3" -EstMinutes 15 -VerificationMethod "Report generated at specified path"

Add-Step -PhaseID $p -PhaseName $pn -StepID "10.2" -Task "Review cluster validation report" `
    -Details "Open and review the HTML report. All tests should pass. Investigate warnings." `
    -Command "Invoke-Item 'C:\Temp\ClusterValidation.html'" `
    -ExpectedResult "Report opens in browser. All critical tests passed." `
    -WhyThisMatters "Validation report identifies misconfigurations that cause cluster instability" `
    -Prerequisite "10.1" -EstMinutes 30 -VerificationMethod "All critical tests show Passed"

Add-Step -PhaseID $p -PhaseName $pn -StepID "10.3" -Task "Resolve any validation failures" `
    -Details "Fix each failed test. Re-run validation after fixes." `
    -Command "Address each failure per report recommendations" `
    -ExpectedResult "All failures resolved. Re-run shows all Passed." `
    -WhyThisMatters "Validation failures indicate real problems that WILL cause issues later" `
    -Prerequisite "10.2" -EstMinutes 30 -VerificationMethod "Re-run Test-Cluster shows no failures"

Add-Step -PhaseID $p -PhaseName $pn -StepID "10.4" -Task "Document warnings and accept as known" `
    -Details "Document acceptable warnings with justification. Save final validation report." `
    -Command "Save validation report with notes on accepted warnings" `
    -ExpectedResult "Warnings documented and final report saved for audit" `
    -WhyThisMatters "Documenting warnings protects you during audits and helps future DBAs" `
    -Prerequisite "10.3" -EstMinutes 10 -VerificationMethod "Report saved with notes"

# ======================================================================
# PHASE 11: Create WSFC Cluster
# ======================================================================
$p = "Phase 11"; $pn = "Create WSFC Cluster"

Add-Step -PhaseID $p -PhaseName $pn -StepID "11.1" -Task "Create the Windows Failover Cluster" `
    -Details "Run New-Cluster with all SQL nodes. Cluster name: $clusterName, IP: $clusterIP" `
    -Command "New-Cluster -Name '$clusterName' -Node $($sqlNodeNames -join ', ') -StaticAddress '$clusterIP' -NoStorage" `
    -ExpectedResult "Cluster created. All nodes joined successfully." `
    -WhyThisMatters "Creates the WSFC that hosts SQL Server AG. Provides heartbeat, quorum, orchestration" `
    -Prerequisite "10.4, 3.6" -EstMinutes 10 -VerificationMethod "Get-Cluster shows Name: $clusterName"

Add-Step -PhaseID $p -PhaseName $pn -StepID "11.2" -Task "Verify cluster nodes and status" `
    -Details "Check all nodes show Status: Up." `
    -Command "Get-ClusterNode | Select-Object Name, State, NodeWeight" `
    -ExpectedResult "All nodes show State: Up" `
    -WhyThisMatters "All nodes must be Up. Down nodes impair cluster functions and AG failover" `
    -Prerequisite "11.1" -EstMinutes 2 -VerificationMethod "All nodes State = Up"

Add-Step -PhaseID $p -PhaseName $pn -StepID "11.3" -Task "Verify cluster IP address" `
    -Details "Confirm cluster IP $clusterIP is online." `
    -Command "Get-ClusterResource | Where-Object { `$_.ResourceType -eq 'IP Address' } | Get-ClusterParameter" `
    -ExpectedResult "Cluster IP $clusterIP is online" `
    -WhyThisMatters "Cluster IP is how management tools reach the cluster" `
    -Prerequisite "11.2" -EstMinutes 3 -VerificationMethod "Cluster resources show Online"

Add-Step -PhaseID $p -PhaseName $pn -StepID "11.4" -Task "Configure cluster network settings" `
    -Details "Configure cluster network priority, enable or disable networks for cluster use based on topology." `
    -Command "Get-ClusterNetwork | Select-Object Name, Role, Address, AddressMask; (Get-ClusterNetwork -Name 'Cluster Network 1').Role = 1; (Get-ClusterNetwork -Name 'Cluster Network 1').Metric = 10000" `
    -ExpectedResult "Cluster networks configured with correct roles and metrics" `
    -WhyThisMatters "Proper network configuration ensures cluster uses correct network for heartbeat and data" `
    -Prerequisite "11.3" -EstMinutes 5 -VerificationMethod "Get-ClusterNetwork shows expected configuration" `
    -Severity Recommended

Add-Step -PhaseID $p -PhaseName $pn -StepID "11.5" -Task "Verify cluster name in DNS" `
    -Details "Confirm $clusterName resolves to $clusterIP" `
    -Command "nslookup $clusterName" `
    -ExpectedResult "DNS resolves $clusterName to $clusterIP" `
    -WhyThisMatters "Cluster management relies on DNS name resolution" `
    -Prerequisite "11.4" -EstMinutes 2 -VerificationMethod "nslookup returns correct IP"

# ======================================================================
# PHASE 12: Configure Cluster Quorum
# ======================================================================
$p = "Phase 12"; $pn = "Configure Cluster Quorum"

Add-Step -PhaseID $p -PhaseName $pn -StepID "12.1" -Task "Understand quorum voting requirements" `
    -Details "In a $totalNodes-node cluster, a witness is needed if node count is even. $witnessDesc provides tie-breaking vote." `
    -Command "Review quorum concepts" `
    -ExpectedResult "Understanding of why $witnessDesc is needed" `
    -WhyThisMatters "Without proper quorum, node failure can cause entire cluster to go offline" `
    -Prerequisite "11.5" -EstMinutes 10 -VerificationMethod "Conceptual understanding confirmed"

switch ($WitnessType) {
    'FileShare' {
        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.2" -Task "Create file share on DC01 for witness" `
            -Details "Create folder D:\ClusterWitness. Share with CNO ${clusterName}$ and svc_cluster Full Control." `
            -Command "New-Item -ItemType Directory -Path 'D:\ClusterWitness' -Force; New-SmbShare -Name 'ClusterWitness' -Path 'D:\ClusterWitness' -FullAccess '$domainNetbios\${clusterName}$', '$domainNetbios\svc_cluster'" `
            -ExpectedResult "Folder shared as \\DC01\ClusterWitness with correct permissions" `
            -WhyThisMatters "File share witness stores tie-breaker vote. Must NOT be on a cluster node" `
            -Prerequisite "12.1" -EstMinutes 10 -VerificationMethod "Get-SmbShare ClusterWitness shows share"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.3" -Task "Configure cluster File Share Witness" `
            -Details "Set quorum to use \\DC01\ClusterWitness as file share witness." `
            -Command "Set-ClusterQuorum -FileShareWitness '\\DC01\ClusterWitness'" `
            -ExpectedResult "Quorum configured with File Share Witness" `
            -WhyThisMatters "Adds tie-breaking vote. Now cluster has $($totalNodes + 1) votes" `
            -Prerequisite "12.2" -EstMinutes 3 -VerificationMethod "Command completes without error"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.5" -Task "Test witness share accessibility" `
            -Details "Verify all nodes can access the witness share." `
            -Command "Test-Path '\\DC01\ClusterWitness\witness.log'; Get-SmbConnection -ServerName DC01" `
            -ExpectedResult "Witness file exists. All nodes can access the share." `
            -WhyThisMatters "If witness is unreachable, it effectively loses its vote" `
            -Prerequisite "12.3" -EstMinutes 5 -VerificationMethod "Witness file accessible from all nodes"
    }
    'Cloud' {
        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.2" -Task "Create Azure Storage account for cloud witness" `
            -Details "Create an Azure Storage account in the same region as the primary datacenter. Note the access key." `
            -Command "New-AzStorageAccount -ResourceGroupName 'HADR-RG' -Name 'hadrwitness' -Location 'EastUS' -SkuName Standard_LRS" `
            -ExpectedResult "Azure Storage account created with access key saved" `
            -WhyThisMatters "Cloud witness uses Azure blob storage as a tie-breaker. No additional infrastructure needed" `
            -Prerequisite "12.1" -EstMinutes 15 -VerificationMethod "Azure portal shows storage account"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.3" -Task "Configure cluster Cloud Witness" `
            -Details "Set quorum to use Azure cloud witness with storage account credentials." `
            -Command "Set-ClusterQuorum -CloudWitness -AccountName 'hadrwitness' -AccessKey '<access-key>'" `
            -ExpectedResult "Cloud Witness configured" `
            -WhyThisMatters "Cloud witness provides off-site tie-breaking without on-premises infrastructure" `
            -Prerequisite "12.2" -EstMinutes 3 -VerificationMethod "Get-ClusterQuorum shows CloudWitness"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.5" -Task "Test cloud witness connectivity" `
            -Details "Verify cluster can communicate with Azure blob storage." `
            -Command "Get-ClusterQuorum | Format-List" `
            -ExpectedResult "Cloud witness shows Online status" `
            -WhyThisMatters "If cloud witness is unreachable, cluster loses tie-breaking vote" `
            -Prerequisite "12.3" -EstMinutes 5 -VerificationMethod "Quorum resource shows Online"
    }
    'Disk' {
        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.2" -Task "Prepare disk witness drive" `
            -Details "Connect a shared disk (iSCSI, FC, or shared VHDX). Format as NTFS. Assign drive letter Q:." `
            -Command "Initialize-Disk -Number <n> -PartitionStyle GPT; New-Partition -DiskNumber <n> -DriveLetter 'Q' -UseMaximumSize; Format-Volume -DriveLetter 'Q' -FileSystem NTFS -NewFileSystemLabel 'Witness'" `
            -ExpectedResult "Disk formatted and assigned drive letter Q:" `
            -WhyThisMatters "Disk witness uses a dedicated shared disk for tie-breaking. Requires shared storage" `
            -Prerequisite "12.1" -EstMinutes 15 -VerificationMethod "Get-Volume Q: shows NTFS formatted"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.3" -Task "Configure cluster Disk Witness" `
            -Details "Set quorum to use the disk witness Q:" `
            -Command "Set-ClusterQuorum -DiskWitness 'Q:'" `
            -ExpectedResult "Disk Witness configured" `
            -WhyThisMatters "Dedicated disk witness provides vote persistence across cluster restarts" `
            -Prerequisite "12.2" -EstMinutes 3 -VerificationMethod "Get-ClusterQuorum shows DiskWitness"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.5" -Task "Verify disk witness accessibility" `
            -Details "Confirm all nodes can access the witness disk." `
            -Command "Get-ClusterResource | Where-Object { `$_.ResourceType -eq 'Physical Disk' } | Get-ClusterParameter" `
            -ExpectedResult "Witness disk online and accessible from all nodes" `
            -WhyThisMatters "Disk witness must be accessible by all nodes to provide quorum" `
            -Prerequisite "12.3" -EstMinutes 5 -VerificationMethod "Disk resource shows Online"
    }
    'None' {
        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.2" -Task "Understand risks of no witness" `
            -Details "Without a witness, an even-node cluster loses quorum if one node fails. This risk is accepted." `
            -Command "Review quorum behavior without witness" `
            -ExpectedResult "Risk understood and accepted by stakeholders" `
            -WhyThisMatters "Without witness, cluster may go offline during single node failure. Not recommended for production" `
            -Prerequisite "12.1" -EstMinutes 5 -VerificationMethod "Risk acceptance documented"

        Add-Step -PhaseID $p -PhaseName $pn -StepID "12.3" -Task "Configure cluster without witness" `
            -Details "Set cluster quorum to Node Majority only." `
            -Command "Set-ClusterQuorum -NodeMajority" `
            -ExpectedResult "Quorum set to Node Majority" `
            -WhyThisMatters "With $totalNodes nodes, majority is $([Math]::Floor($totalNodes/2)+1) nodes" `
            -Prerequisite "12.2" -EstMinutes 3 -VerificationMethod "Get-ClusterQuorum shows NodeMajority"
    }
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "12.4" -Task "Verify quorum configuration" `
    -Details "Confirm quorum type and resource are set correctly." `
    -Command "Get-ClusterQuorum | Format-List" `
    -ExpectedResult "Quorum configuration matches planned witness type" `
    -WhyThisMatters "Confirms quorum is set correctly before AG creation" `
    -Prerequisite "12.3" -EstMinutes 2 -VerificationMethod "Get-ClusterQuorum shows correct config"

# ======================================================================
# PHASE 13: Configure SQL Server HADR Endpoints
# ======================================================================
$p = "Phase 13"; $pn = "Configure SQL Server HADR Endpoints"

foreach ($node in $sqlNodeNames) {
    $idx = [array]::IndexOf($sqlNodeNames, $node) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "13.$idx.1" -Task "Create HADR endpoint on $node" `
        -Details "Create endpoint on TCP 5022 with DATABASE_MIRRORING role = ALL." `
        -Command "CREATE ENDPOINT Hadr_endpoint STATE = STARTED AS TCP (LISTENER_PORT = 5022) FOR DATABASE_MIRRORING (ROLE = ALL);" `
        -ExpectedResult "Endpoint Hadr_endpoint created on $node" `
        -WhyThisMatters "Endpoint is the communication pipe for AG data movement between replicas" `
        -Prerequisite "8.1.5" -EstMinutes 3 -VerificationMethod "SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint'"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "13.$idx.2" -Task "Grant CONNECT on endpoint to service account on $node" `
        -Details "Grant $domainNetbios\svc_sql CONNECT permission on the endpoint." `
        -Command "GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [$domainNetbios\svc_sql];" `
        -ExpectedResult "Permission granted" `
        -WhyThisMatters "Service account needs permission to use the endpoint for AG communication" `
        -Prerequisite "13.$idx.1" -EstMinutes 2 -VerificationMethod "Check via sys.endpoint_permissions"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "13.1.3" -Task "Verify endpoints on ALL nodes" `
    -Details "Confirm endpoints are STARTED on port 5022 across all nodes." `
    -Command "SELECT name, type_desc, state_desc, port FROM sys.endpoints WHERE type_desc = 'DATABASE_MIRRORING';" `
    -ExpectedResult "All nodes show state_desc = STARTED on port 5022" `
    -WhyThisMatters "If any endpoint is STOPPED or DISABLED, AG communication fails" `
    -Prerequisite "13.$($totalNodes).2" -EstMinutes 3 -VerificationMethod "All endpoints show STARTED"

# ======================================================================
# PHASE 14: Windows Firewall Configuration
# ======================================================================
$p = "Phase 14"; $pn = "Windows Firewall Configuration"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.1" -Task "Open firewall port 1433 (SQL Server)" `
    -Details "Create inbound rule on all SQL nodes to allow TCP 1433." `
    -Command "New-NetFirewallRule -DisplayName 'SQL Server 1433' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow" `
    -ExpectedResult "Rule created on all SQL nodes. Port 1433 open." `
    -WhyThisMatters "Port 1433 is the default SQL Server port for client and listener connections" `
    -Prerequisite "7.1.13" -EstMinutes 3 -VerificationMethod "Get-NetFirewallRule shows Enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.2" -Task "Open firewall port 5022 (AG Endpoint)" `
    -Details "Create inbound rule on all SQL nodes to allow TCP 5022." `
    -Command "New-NetFirewallRule -DisplayName 'SQL AG Endpoint 5022' -Direction Inbound -Protocol TCP -LocalPort 5022 -Action Allow" `
    -ExpectedResult "Port 5022 open on all SQL nodes" `
    -WhyThisMatters "AG synchronization sends log blocks over port 5022" `
    -Prerequisite "13.1.3" -EstMinutes 3 -VerificationMethod "Rule created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.3" -Task "Open firewall port 3343 (WSFC)" `
    -Details "Create inbound rules on all SQL nodes for TCP and UDP 3343." `
    -Command "New-NetFirewallRule -DisplayName 'WSFC 3343' -Direction Inbound -Protocol TCP -LocalPort 3343 -Action Allow; New-NetFirewallRule -DisplayName 'WSFC 3343 UDP' -Direction Inbound -Protocol UDP -LocalPort 3343 -Action Allow" `
    -ExpectedResult "Port 3343 open on all nodes (TCP and UDP)" `
    -WhyThisMatters "WSFC uses port 3343 for heartbeat and cluster communication" `
    -Prerequisite "11.5" -EstMinutes 3 -VerificationMethod "Rules created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.4" -Task "Open firewall port 445 for file share witness" `
    -Details "Ensure port 445 is open on the file share witness server for SMB access." `
    -Command "New-NetFirewallRule -DisplayName 'SMB 445 Witness' -Direction Inbound -Protocol TCP -LocalPort 445 -Action Allow" `
    -ExpectedResult "Port 445 open for witness access" `
    -WhyThisMatters "File share witness is accessed via SMB on port 445" `
    -Prerequisite "12.4" -EstMinutes 2 -VerificationMethod "Rule created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.5" -Task "Open firewall port 135 (RPC for cluster management)" `
    -Details "Create inbound rule for TCP 135 on all cluster nodes." `
    -Command "New-NetFirewallRule -DisplayName 'RPC 135 Cluster' -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow" `
    -ExpectedResult "Port 135 open on all nodes" `
    -WhyThisMatters "Failover Cluster Manager uses RPC for remote cluster management" `
    -Prerequisite "11.5" -EstMinutes 2 -VerificationMethod "Rule created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.6" -Task "Open firewall port 1434 (SQL Browser / DAC port)" `
    -Details "Create inbound rule for UDP 1434 (SQL Browser) and TCP 1434 (Dedicated Admin Connection)." `
    -Command "New-NetFirewallRule -DisplayName 'SQL Browser 1434' -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow; New-NetFirewallRule -DisplayName 'SQL DAC 1434' -Direction Inbound -Protocol TCP -LocalPort 1434 -Action Allow" `
    -ExpectedResult "Port 1434 open (TCP and UDP) on all SQL nodes" `
    -WhyThisMatters "SQL Browser helps clients find instances. DAC allows emergency admin connection when SQL is unresponsive" `
    -Prerequisite "7.1.13" -EstMinutes 3 -VerificationMethod "Rules created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.7" -Task "Create rule for dynamic RPC ports (cluster)" `
    -Details "Allow dynamic RPC port range (49152-65535) for WSFC internal communications." `
    -Command "New-NetFirewallRule -DisplayName 'Cluster Dynamic RPC' -Direction Inbound -Protocol TCP -LocalPort 49152-65535 -Action Allow" `
    -ExpectedResult "Dynamic RPC ports allowed" `
    -WhyThisMatters "WSFC uses dynamic RPC ports for various internal communications" `
    -Prerequisite "11.5" -EstMinutes 3 -VerificationMethod "Rule created and enabled"

Add-Step -PhaseID $p -PhaseName $pn -StepID "14.8" -Task "Verify firewall rules by testing port connectivity" `
    -Details "From each server, use Test-NetConnection to verify all required ports." `
    -Command "$(foreach ($n in $sqlNodeNames) { "Test-NetConnection $n -Port 1433; Test-NetConnection $n -Port 5022; " })" `
    -ExpectedResult "All Test-NetConnection return TcpTestSucceeded: True" `
    -WhyThisMatters "Creating rules doesn't guarantee they work. Test-NetConnection confirms actual connectivity" `
    -Prerequisite "14.7" -EstMinutes 10 -VerificationMethod "All port tests succeed"

# ======================================================================
# PHASE 15: Create Test Database and Prepare for AG
# ======================================================================
$p = "Phase 15"; $pn = "Create Test Database and Prepare for AG"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.1" -Task "Connect to $primaryNode using SSMS" `
    -Details "Open SSMS and connect to $primaryNode using Windows Authentication." `
    -Command "ssms.exe" `
    -ExpectedResult "Connected to $primaryNode in SSMS Object Explorer" `
    -WhyThisMatters "SSMS provides a graphical interface for SQL management" `
    -Prerequisite "7.1.13" -EstMinutes 2 -VerificationMethod "SSMS shows $primaryNode connected"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.2" -Task "Create a test database (SalesDB)" `
    -Details "Create SalesDB with data file on D:\, log file on L:\. Set initial sizes and autogrowth." `
    -Command "CREATE DATABASE SalesDB ON (NAME = SalesDB_Data, FILENAME = 'D:\MSSQL\Data\SalesDB.mdf', SIZE = 100MB, FILEGROWTH = 64MB) LOG ON (NAME = SalesDB_Log, FILENAME = 'L:\MSSQL\Log\SalesDB_log.ldf', SIZE = 50MB, FILEGROWTH = 64MB);" `
    -ExpectedResult "Database SalesDB created" `
    -WhyThisMatters "Need at least one database to add to an AG for validation" `
    -Prerequisite "15.1" -EstMinutes 5 -VerificationMethod "SELECT name FROM sys.databases WHERE name='SalesDB'"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.3" -Task "Change recovery model to FULL" `
    -Details "Set database recovery model to FULL (mandatory for AG)." `
    -Command "ALTER DATABASE SalesDB SET RECOVERY FULL;" `
    -ExpectedResult "Recovery model set to Full" `
    -WhyThisMatters "AG works by shipping transaction log records. FULL recovery ensures every transaction is logged" `
    -Prerequisite "15.2" -EstMinutes 2 -VerificationMethod "SELECT recovery_model_desc FROM sys.databases WHERE name='SalesDB' returns FULL"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.4" -Task "Take a full database backup" `
    -Details "Create full backup of SalesDB to initialize the secondary replica." `
    -Command "BACKUP DATABASE SalesDB TO DISK = 'D:\MSSQL\Backup\SalesDB_Full.bak' WITH FORMAT, INIT, NAME = 'SalesDB-FullBackup';" `
    -ExpectedResult "Backup completed successfully" `
    -WhyThisMatters "Full backup is REQUIRED to initialize the secondary replica for AG" `
    -Prerequisite "15.3" -EstMinutes 10 -VerificationMethod "Backup file exists"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.5" -Task "Take a transaction log backup" `
    -Details "Back up the transaction log for log chain continuity." `
    -Command "BACKUP LOG SalesDB TO DISK = 'D:\MSSQL\Backup\SalesDB_Log.trn' WITH INIT, NAME = 'SalesDB-LogBackup';" `
    -ExpectedResult "Log backup completed successfully" `
    -WhyThisMatters "Full + log backup = complete restore point. Maintains log chain continuity" `
    -Prerequisite "15.4" -EstMinutes 5 -VerificationMethod "Backup file exists"

Add-Step -PhaseID $p -PhaseName $pn -StepID "15.6" -Task "Create sample data for sync verification" `
    -Details "Create test table and insert data to verify replication after AG setup." `
    -Command "USE SalesDB; CREATE TABLE dbo.Products (ProductID INT IDENTITY(1,1) PRIMARY KEY, ProductName NVARCHAR(100), Price DECIMAL(10,2), CreatedDate DATETIME DEFAULT GETDATE()); INSERT INTO dbo.Products (ProductName, Price) VALUES ('Widget A', 19.99), ('Widget B', 29.99), ('Gadget C', 49.99);" `
    -ExpectedResult "Table created with 3 rows of data" `
    -WhyThisMatters "After AG setup, query this on secondary to confirm replication works" `
    -Prerequisite "15.2" -EstMinutes 5 -VerificationMethod "SELECT COUNT(*) FROM dbo.Products returns 3"

# ======================================================================
# PHASE 16: Restore Database on Secondary Nodes
# ======================================================================
$p = "Phase 16"; $pn = "Restore Database on Secondary Nodes"

foreach ($secondaryNode in $secondaryNodes) {
    $sIdx = [array]::IndexOf($secondaryNodes, $secondaryNode) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "16.$sIdx.1" -Task "Copy backup files to $secondaryNode" `
        -Details "Copy full and log backups from $primaryNode to $secondaryNode." `
        -Command "Copy-Item -Path '\\$primaryNode\D`$MSSQL\`$Backup\SalesDB_Full.bak' -Destination 'D:\`$MSSQL\`$Backup\'; Copy-Item -Path '\\$primaryNode\D`$MSSQL\`$Backup\SalesDB_Log.trn' -Destination 'D:\`$MSSQL\`$Backup\'" `
        -ExpectedResult "Backup files exist on $secondaryNode" `
        -WhyThisMatters "Secondary needs backup files to restore the database" `
        -Prerequisite "15.5" -EstMinutes 5 -VerificationMethod "Test-Path confirms files exist"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "16.$sIdx.2" -Task "Restore full backup WITH NORECOVERY on $secondaryNode" `
        -Details "Restore SalesDB with NORECOVERY to keep it in Restoring state for AG." `
        -Command "RESTORE DATABASE SalesDB FROM DISK = 'D:\MSSQL\Backup\SalesDB_Full.bak' WITH NORECOVERY, MOVE 'SalesDB_Data' TO 'D:\MSSQL\Data\SalesDB.mdf', MOVE 'SalesDB_Log' TO 'L:\MSSQL\Log\SalesDB_log.ldf';" `
        -ExpectedResult "Restore completed. Database shows '(Restoring...)'" `
        -WhyThisMatters "NORECOVERY is MANDATORY. AG cannot take ownership if database is in RECOVERY state" `
        -Prerequisite "16.$sIdx.1" -EstMinutes 10 -VerificationMethod "SELECT state_desc FROM sys.databases WHERE name='SalesDB' returns RESTORING"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "16.$sIdx.3" -Task "Restore log backup WITH NORECOVERY on $secondaryNode" `
        -Details "Restore log backup to bring database to consistent point, still in NORECOVERY." `
        -Command "RESTORE LOG SalesDB FROM DISK = 'D:\MSSQL\Backup\SalesDB_Log.trn' WITH NORECOVERY;" `
        -ExpectedResult "Log restore completed. Database still in Restoring state." `
        -WhyThisMatters "Applies transactions from log backup. Database stays ready for AG takeover" `
        -Prerequisite "16.$sIdx.2" -EstMinutes 5 -VerificationMethod "Database still in RESTORING state"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "16.$sIdx.4" -Task "Verify NORECOVERY state on $secondaryNode" `
        -Details "Confirm database is in RESTORING state and file paths are correct." `
        -Command "SELECT name, physical_name, state_desc FROM sys.master_files WHERE database_id = DB_ID('SalesDB');" `
        -ExpectedResult "state_desc = RESTORING. File paths on D: and L: drives." `
        -WhyThisMatters "If accidentally restored WITH RECOVERY, must restore again" `
        -Prerequisite "16.$sIdx.3" -EstMinutes 2 -VerificationMethod "state_desc shows RESTORING"
}

# ======================================================================
# PHASE 17: Create Availability Group
# ======================================================================
$p = "Phase 17"; $pn = "Create Availability Group"

# Build replica clause - synchronous for first secondary, async for additional
$replicaClauses = @()
$isFirstSecondary = $true
foreach ($node in $sqlNodeNames) {
    if ($node -eq $primaryNode) { continue }
    $availMode = if ($isFirstSecondary) { 'SYNCHRONOUS_COMMIT' } else { 'ASYNCHRONOUS_COMMIT' }
    $failoverMode = if ($isFirstSecondary) { 'AUTOMATIC' } else { 'MANUAL' }
    $allowConnections = if ($IncludeReadableSecondary -or !$isFirstSecondary) { 'ALL' } else { 'NONE' }
    $replicaClauses += "N'$node' WITH (ENDPOINT_URL = N'TCP://$node.$domain`:5022', FAILOVER_MODE = $failoverMode, AVAILABILITY_MODE = $availMode, SECONDARY_ROLE(ALLOW_CONNECTIONS = $allowConnections))"
    $isFirstSecondary = $false
}
$replicaSQL = $replicaClauses -join ', '

Add-Step -PhaseID $p -PhaseName $pn -StepID "17.1" -Task "Create the Availability Group on $primaryNode" `
    -Details "Create AG named $agName with SalesDB and configured replicas." `
    -Command "CREATE AVAILABILITY GROUP $agName FOR DATABASE SalesDB REPLICA ON $replicaSQL;" `
    -ExpectedResult "AG $agName created on $primaryNode" `
    -WhyThisMatters "Creates the AG container defining which databases are replicated and how" `
    -Prerequisite "16.$($secondaryNodes.Count).4, 13.1.3" -EstMinutes 5 -VerificationMethod "SELECT name FROM sys.availability_groups returns $agName"

Add-Step -PhaseID $p -PhaseName $pn -StepID "17.2" -Task "Verify AG configuration" `
    -Details "Check AG and replica details match planned configuration." `
    -Command "SELECT ag.name AS AGName, ar.replica_server_name, ar.endpoint_url, ar.availability_mode_desc, ar.failover_mode_desc FROM sys.availability_groups ag JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id;" `
    -ExpectedResult "All replicas listed with correct settings" `
    -WhyThisMatters "Verify replica settings before joining secondaries. Fewer surprises later" `
    -Prerequisite "17.1" -EstMinutes 2 -VerificationMethod "All replicas shown with correct parameters"

# ======================================================================
# PHASE 18: Join Secondary Replicas to AG
# ======================================================================
$p = "Phase 18"; $pn = "Join Secondary Replicas to Availability Group"

foreach ($secondaryNode in $secondaryNodes) {
    $sIdx = [array]::IndexOf($secondaryNodes, $secondaryNode) + 1
    Add-Step -PhaseID $p -PhaseName $pn -StepID "18.$sIdx.1" -Task "Connect to $secondaryNode and join the AG" `
        -Details "Run ALTER AVAILABILITY GROUP to join $secondaryNode to $agName." `
        -Command "ALTER AVAILABILITY GROUP $agName JOIN;" `
        -ExpectedResult "$secondaryNode joined to $agName" `
        -WhyThisMatters "Without JOIN, secondary is unaware of AG and cannot receive data" `
        -Prerequisite "17.2" -EstMinutes 2 -VerificationMethod "SELECT replica_server_name FROM sys.availability_replicas WHERE replica_server_name='$secondaryNode'"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "18.$sIdx.2" -Task "Join the database to the AG on $secondaryNode" `
        -Details "Add SalesDB to the AG on $secondaryNode. Brings it online from RESTORING state." `
        -Command "ALTER DATABASE SalesDB SET HADR AVAILABILITY GROUP = $agName;" `
        -ExpectedResult "Database leaves RESTORING state and becomes secondary replica" `
        -WhyThisMatters "This brings the restored database online as secondary and starts synchronization" `
        -Prerequisite "18.$sIdx.1, 16.$sIdx.4" -EstMinutes 2 -VerificationMethod "SELECT state_desc FROM sys.databases WHERE name='SalesDB' returns ONLINE"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "18.$sIdx.3" -Task "Verify database synchronization on $secondaryNode" `
        -Details "Check synchronization state is SYNCHRONIZED/HEALTHY." `
        -Command "SELECT replica_server_name, synchronization_state_desc, synchronization_health_desc FROM sys.dm_hadr_database_replica_states drs JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id;" `
        -ExpectedResult "Both replicas show SYNCHRONIZED and HEALTHY" `
        -WhyThisMatters "SYNCHRONIZED = secondary has all data up to last committed transaction" `
        -Prerequisite "18.$sIdx.2" -EstMinutes 2 -VerificationMethod "Both replicas show SYNCHRONIZED/HEALTHY"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "18.$sIdx.4" -Task "Check data consistency on $secondaryNode" `
        -Details "If readable secondary is configured, query data on $secondaryNode. Or fail over and verify." `
        -Command "SELECT COUNT(*) FROM SalesDB.dbo.Products ON $secondaryNode (if readable)" `
        -ExpectedResult "Data matches between primary and secondary" `
        -WhyThisMatters "Ensures data replication is working correctly end-to-end" `
        -Prerequisite "18.$sIdx.3" -EstMinutes 5 -VerificationMethod "Row counts match on all replicas"
}

# ======================================================================
# PHASE 19: Create AG Listener
# ======================================================================
$p = "Phase 19"; $pn = "Create Availability Group Listener"

Add-Step -PhaseID $p -PhaseName $pn -StepID "19.1" -Task "Understand Listener purpose" `
    -Details "The Listener provides a constant DNS name/IP that applications use to connect. After failover, listener points to new primary." `
    -Command "No command - conceptual understanding" `
    -ExpectedResult "Understanding of listener benefits" `
    -WhyThisMatters "Without listener, applications must connect to server name, breaking after failover" `
    -Prerequisite "18.$($secondaryNodes.Count).3" -EstMinutes 3 -VerificationMethod "Concept understanding"

Add-Step -PhaseID $p -PhaseName $pn -StepID "19.2" -Task "Create the AG Listener" `
    -Details "Create listener $listenerName with IP $listenerIP on port 1433." `
    -Command "ALTER AVAILABILITY GROUP $agName ADD LISTENER '$listenerName' (WITH IP ((N'$listenerIP', N'$subnet')), PORT = 1433);" `
    -ExpectedResult "Listener $listenerName created" `
    -WhyThisMatters "Listener provides constant connection point for applications" `
    -Prerequisite "19.1" -EstMinutes 2 -VerificationMethod "SELECT listener_dns_name FROM sys.availability_group_listeners returns $listenerName"

Add-Step -PhaseID $p -PhaseName $pn -StepID "19.3" -Task "Verify listener in Cluster Manager" `
    -Details "Check listener resource is Online in Failover Cluster Manager." `
    -Command "Get-ClusterGroup -Name '$agName' | Get-ClusterResource | Select Name, State" `
    -ExpectedResult "Listener resource shows State: Online" `
    -WhyThisMatters "Listener is a cluster resource managed by WSFC. If offline, apps can't connect" `
    -Prerequisite "19.2" -EstMinutes 3 -VerificationMethod "Cluster resource shows Online"

if ($IncludeReadableSecondary) {
    $rrCmd = foreach ($n in $sqlNodeNames) {
        "ALTER AVAILABILITY GROUP $agName MODIFY REPLICA ON N'$n' WITH (SECONDARY_ROLE(READ_ONLY_ROUTING_URL = N'TCP://$n.$domain`:1433')); "
    }
    $rrCmd += foreach ($n in $sqlNodeNames) {
        $others = ($sqlNodeNames | Where-Object { $_ -ne $n }) -join "', '"
        "ALTER AVAILABILITY GROUP $agName MODIFY REPLICA ON N'$n' WITH (PRIMARY_ROLE(READ_ONLY_ROUTING_LIST = ('$others'))); "
    }
    Add-Step -PhaseID $p -PhaseName $pn -StepID "19.4" -Task "Configure read-only routing for secondary replicas" `
        -Details "Set read-only routing URL on each replica and configure routing list." `
        -Command ($rrCmd -join '') `
        -ExpectedResult "Read-only routing configured on all replicas" `
        -WhyThisMatters "Read-only routing directs reporting queries to secondary, reducing primary load" `
        -Prerequisite "19.2" -EstMinutes 10 -VerificationMethod "SELECT read_only_routing_url FROM sys.availability_replicas shows configured URLs"
}

Add-Step -PhaseID $p -PhaseName $pn -StepID "19.$(if ($IncludeReadableSecondary) { 5 } else { 4 })" -Task "Verify listener in DNS and test connectivity" `
    -Details "Test DNS resolution and SQL connection to the listener." `
    -Command "nslookup $listenerName; sqlcmd -S $listenerName -E -Q 'SELECT @@SERVERNAME'" `
    -ExpectedResult "nslookup resolves to $listenerIP. sqlcmd connects successfully." `
    -WhyThisMatters "If DNS doesn't resolve or sqlcmd can't connect, apps will also fail" `
    -Prerequisite "19.3" -EstMinutes 5 -VerificationMethod "Listener connection successful"

# ======================================================================
# PHASE 20: Test Failover Scenarios
# ======================================================================
$p = "Phase 20"; $pn = "Test Failover Scenarios"

Add-Step -PhaseID $p -PhaseName $pn -StepID "20.1" -Task "Test manual planned failover (graceful)" `
    -Details "Perform a planned failover to $($secondaryNodes[0]) with no data loss." `
    -Command "On $($secondaryNodes[0]): ALTER AVAILABILITY GROUP $agName FAILOVER;" `
    -ExpectedResult "Failover succeeds. $($secondaryNodes[0]) becomes primary." `
    -WhyThisMatters "Planned failover is used for patching and maintenance. Must work correctly" `
    -Prerequisite "19.4" -EstMinutes 3 -VerificationMethod "SELECT @@SERVERNAME returns $($secondaryNodes[0])"

Add-Step -PhaseID $p -PhaseName $pn -StepID "20.2" -Task "Verify data integrity after failover" `
    -Details "Connect via listener and verify data is intact after failover." `
    -Command "sqlcmd -S $listenerName -E -Q 'SELECT @@SERVERNAME AS [Current Primary]; SELECT COUNT(*) AS [RowCount] FROM SalesDB.dbo.Products'" `
    -ExpectedResult "Shows new primary and row count = 3 (data intact)" `
    -WhyThisMatters "Confirms listener points correctly and no data loss during failover" `
    -Prerequisite "20.1" -EstMinutes 2 -VerificationMethod "Data and connectivity verified"

Add-Step -PhaseID $p -PhaseName $pn -StepID "20.3" -Task "Fail back to $primaryNode (original primary)" `
    -Details "Fail the AG back to $primaryNode after maintenance." `
    -Command "On $primaryNode`: ALTER AVAILABILITY GROUP $agName FAILOVER;" `
    -ExpectedResult "$primaryNode becomes primary again" `
    -WhyThisMatters "Original primary is usually in primary datacenter with better connectivity" `
    -Prerequisite "20.2" -EstMinutes 3 -VerificationMethod "SELECT @@SERVERNAME returns $primaryNode"

if ($SecondaryReplicas -ge 2) {
    Add-Step -PhaseID $p -PhaseName $pn -StepID "20.4" -Task "Test failover to async replica" `
        -Details "Fail over to an ASYNCHRONOUS_COMMIT replica using FORCE_FAILOVER_ALLOW_DATA_LOSS." `
        -Command "On $($secondaryNodes[-1]): ALTER AVAILABILITY GROUP $agName FORCE_FAILOVER_ALLOW_DATA_LOSS;" `
        -ExpectedResult "Failover to async replica succeeds" `
        -WhyThisMatters "Async replicas are for DR scenarios. Forced failover may cause data loss - must understand behavior" `
        -Prerequisite "20.3" -EstMinutes 5 -VerificationMethod "New primary shows as $($secondaryNodes[-1])"

    Add-Step -PhaseID $p -PhaseName $pn -StepID "20.5" -Task "Fail back to $primaryNode and verify resync" `
        -Details "Fail back and confirm all replicas resynchronize." `
        -Command "On $primaryNode`: ALTER AVAILABILITY GROUP $agName FAILOVER; SELECT synchronization_state_desc, synchronization_health_desc FROM sys.dm_hadr_database_replica_states;" `
        -ExpectedResult "$primaryNode is primary. All replicas SYNCHRONIZED/HEALTHY" `
        -WhyThisMatters "After DR failover test, system must return to normal operation with all replicas in sync" `
        -Prerequisite "20.4" -EstMinutes 5 -VerificationMethod "All replicas show SYNCHRONIZED/HEALTHY"
}

$failoverOffset = if ($SecondaryReplicas -ge 2) { 6 } else { 4 }
Add-Step -PhaseID $p -PhaseName $pn -StepID "20.$failoverOffset" -Task "Test automatic failover (force crash simulation)" `
    -Details "Simulate primary crash by stopping SQL service. Test that automatic failover occurs." `
    -Command "Stop-Service MSSQLSERVER -Force on $primaryNode; Verify connection via listener" `
    -ExpectedResult "$($secondaryNodes[0]) becomes primary automatically" `
    -WhyThisMatters "Automatic failover is the key benefit. Validates self-healing capability" `
    -Prerequisite "20.3" -EstMinutes 5 -VerificationMethod "Connection to listener succeeds on new primary"

Add-Step -PhaseID $p -PhaseName $pn -StepID "20.$(if ($SecondaryReplicas -ge 2) { 7 } else { 5 })" -Task "Restart failed primary and verify rejoin" `
    -Details "Start the failed primary server and confirm it rejoins the AG." `
    -Command "Start-Service MSSQLSERVER on $primaryNode; SELECT synchronization_state_desc, synchronization_health_desc FROM sys.dm_hadr_database_replica_states;" `
    -ExpectedResult "$primaryNode rejoins as secondary. All replicas SYNCHRONIZED/HEALTHY" `
    -WhyThisMatters "After crash, failed server should automatically rejoin and catch up" `
    -Prerequisite "20.$failoverOffset" -EstMinutes 10 -VerificationMethod "All nodes show SYNCHRONIZED/HEALTHY"

Add-Step -PhaseID $p -PhaseName $pn -StepID "20.$(if ($SecondaryReplicas -ge 2) { 8 } else { 6 })" -Task "Test failover with active connections" `
    -Details "Run continuous query via listener while performing failover. Verify connection survives." `
    -Command "WHILE 1=1 BEGIN SELECT @@SERVERNAME, GETDATE(); WAITFOR DELAY '00:00:01'; END; Then failover." `
    -ExpectedResult "Query pauses briefly during failover but resumes automatically" `
    -WhyThisMatters "Applications have persistent connections. Must verify they survive failover" `
    -Prerequisite "20.$(if ($SecondaryReplicas -ge 2) { 7 } else { 5 })" -EstMinutes 10 -VerificationMethod "Connection survives failover with minimal interruption"

# ======================================================================
# PHASE 21: Configure Monitoring and Alerts
# ======================================================================
$p = "Phase 21"; $pn = "Configure Monitoring and Alerts"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.1" -Task "Set up SQL Agent alerts for AG state changes" `
    -Details "Create alert on AG role change event (message 1480)." `
    -Command "EXEC msdb.dbo.sp_add_alert @name=N'AG Role Change', @message_id=1480, @severity=0, @enabled=1, @delay_between_responses=60;" `
    -ExpectedResult "Alert created" `
    -WhyThisMatters "Without alerts, you won't know when AG state changes until users report issues" `
    -Prerequisite "7.1.13" -EstMinutes 5 -VerificationMethod "SELECT * FROM msdb.dbo.sysalerts WHERE name='AG Role Change'"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.2" -Task "Create AG health monitoring job" `
    -Details "Create SQL Agent job to check AG health every minute and notify on issues." `
    -Command "Create SQL Agent Job 'AG Health Monitor' with 1-min schedule: SELECT synchronization_state_desc, synchronization_health_desc FROM sys.dm_hadr_database_replica_states WHERE synchronization_health_desc != 'HEALTHY';" `
    -ExpectedResult "Job created with 1-minute schedule" `
    -WhyThisMatters "Real-time monitoring catches issues before they become critical" `
    -Prerequisite "21.1" -EstMinutes 15 -VerificationMethod "Job exists and runs successfully"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.3" -Task "Configure Database Mail for notifications" `
    -Details "Enable Database Mail and configure SMTP profile for DBA alerts." `
    -Command "EXEC msdb.dbo.sysmail_add_account_sp @account_name='DBA Alerts', @email_address='sqlalerts@corp.local', @mailserver_name='smtp.corp.local'; EXEC msdb.dbo.sysmail_add_profile_sp @profile_name='DBA Profile';" `
    -ExpectedResult "Database Mail configured and operational" `
    -WhyThisMatters "Email notifications ensure DBA team is informed immediately of AG issues" `
    -Prerequisite "21.2" -EstMinutes 10 -VerificationMethod "EXEC msdb.dbo.sysmail_help_status_sp returns 'STARTED'"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.4" -Task "Create AG monitoring queries script" `
    -Details "Save essential DMV queries for AG monitoring to standard location." `
    -Command "Save query script with replica health, sync state, log send queue, cluster health checks" `
    -ExpectedResult "Script file saved at D:\Scripts\AG_Monitoring.sql" `
    -WhyThisMatters "Standardized scripts ensure every DBA checks the same things the same way" `
    -Prerequisite "18.$($secondaryNodes.Count).3" -EstMinutes 10 -VerificationMethod "Script file exists"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.5" -Task "Configure log shipping queue monitoring" `
    -Details "Set up alerts when log send queue exceeds threshold (e.g., > 1GB). High queue indicates sync issues." `
    -Command "Create alert on condition: SELECT COUNT(*) FROM sys.dm_hadr_database_replica_states WHERE log_send_queue_size_kb > 1048576" `
    -ExpectedResult "Queue monitoring configured with alert threshold" `
    -WhyThisMatters "High log send queue indicates network or performance issues between replicas" `
    -Prerequisite "21.4" -EstMinutes 10 -VerificationMethod "Alert configured and verified"

Add-Step -PhaseID $p -PhaseName $pn -StepID "21.6" -Task "Set up Windows Event monitoring for cluster events" `
    -Details "Configure Windows Event Log subscription or forwarder to monitor cluster and AG related events." `
    -Command "wevtutil qe Microsoft-Windows-FailoverClustering/Operational /c:5 /e:Events /f:text" `
    -ExpectedResult "Windows Event monitoring configured for cluster events" `
    -WhyThisMatters "Cluster and AG events are logged in Windows Event Log. Monitoring these catches infrastructure issues" `
    -Prerequisite "11.5" -EstMinutes 15 -VerificationMethod "Event log query returns results without errors"

# ======================================================================
# PHASE 22: Operational Housekeeping & Final Verification
# ======================================================================
$p = "Phase 22"; $pn = "Operational Housekeeping & Final Verification"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.1" -Task "Configure backup strategy for AG databases" `
    -Details "Full/diff backups on primary, log backups on secondary (to offload I/O). Create SQL Agent backup jobs." `
    -Command "Create job: Full backup daily on primary; $(if ($IncludeBackupOnSecondary) { "Log backup every 15 min on $($secondaryNodes[0])" } else { "Log backup every 15 min on primary" })" `
    -ExpectedResult "Backup jobs created and scheduled" `
    -WhyThisMatters "AG databases still need backups! Backups protect against logical corruption (AG replicates corruption too)" `
    -Prerequisite "18.$($secondaryNodes.Count).3" -EstMinutes 15 -VerificationMethod "Backup jobs exist and run successfully"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.2" -Task "Run DBCC CHECKDB on all replicas" `
    -Details "Run integrity checks on primary (and secondary if readable) to ensure database is physically consistent." `
    -Command "DBCC CHECKDB('SalesDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;" `
    -ExpectedResult "DBCC CHECKDB completed with no errors on all replicas" `
    -WhyThisMatters "DBCC CHECKDB validates physical and logical integrity. AG replicates corruption - catch it before it spreads" `
    -Prerequisite "18.$($secondaryNodes.Count).3" -EstMinutes 20 -VerificationMethod "CHECKDB output shows 0 allocation errors and 0 consistency errors"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.3" -Task "Create Disaster Recovery (DR) runbook" `
    -Details "Document step-by-step DR procedures: failover steps, failback steps, contact list, RPO/RTO targets, escalation process." `
    -Command "Create DR runbook document with failover/fallback procedures and RPO/RTO targets" `
    -ExpectedResult "DR runbook completed and stored in shared location" `
    -WhyThisMatters "During a real disaster, stress is high. A runbook ensures consistent, correct response" `
    -Prerequisite "22.2" -EstMinutes 30 -VerificationMethod "Runbook reviewed and approved by team"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.4" -Task "Verify all cluster and AG resources are online" `
    -Details "Comprehensive health check of all cluster and AG resources. Document baseline state." `
    -Command "Get-ClusterGroup; Get-ClusterResource; SELECT * FROM sys.dm_hadr_availability_replica_states; SELECT * FROM sys.dm_hadr_database_replica_states;" `
    -ExpectedResult "All resources Online. All replicas SYNCHRONIZED/HEALTHY." `
    -WhyThisMatters "Comprehensive check ensures nothing missed. Baseline helps identify changes later" `
    -Prerequisite "22.3" -EstMinutes 10 -VerificationMethod "All checks pass and baseline documented"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.5" -Task "Perform final HADR health review" `
    -Details "Review complete HADR setup against best practices. Check: quorum, failover mode, backup location, monitoring, alerts, DR plan." `
    -Command "Review checklist with entire implementation team" `
    -ExpectedResult "All items reviewed and signed off by stakeholders" `
    -WhyThisMatters "Final review catches anything missed. Sign-off ensures team accountability" `
    -Prerequisite "22.4" -EstMinutes 30 -VerificationMethod "Health review document completed and signed"

Add-Step -PhaseID $p -PhaseName $pn -StepID "22.6" -Task "Document the entire HADR configuration" `
    -Details "Create comprehensive document with: all IPs, service accounts, AG name, listener details, firewall rules, backup strategy, monitoring, failover procedures." `
    -Command "Save documentation to shared location: \\DC01\Shared\HADR_Configuration.docx" `
    -ExpectedResult "Configuration document completed and saved to shared location" `
    -WhyThisMatters "Complete documentation ensures any DBA can take over management. Satisfies audit requirements" `
    -Prerequisite "22.5" -EstMinutes 30 -VerificationMethod "Document exists and reviewed by team lead"

# ======================================================================
# Convert steps to JSON for HTML embedding
# ======================================================================
$stepsJson = $steps | ConvertTo-Json -Depth 10

# ======================================================================
# Group phases and compute statistics
# ======================================================================
$phasesList = $steps | Group-Object PhaseName | ForEach-Object {
    $phaseSteps = $_.Group
    $total = $phaseSteps.Count
    $completed = ($phaseSteps | Where-Object { $_.Status -eq 'Completed' }).Count
    [PSCustomObject]@{
        PhaseID   = $phaseSteps[0].PhaseID
        PhaseName = $_.Name
        Total     = $total
        Completed = $completed
    }
}
$phasesJson = $phasesList | ConvertTo-Json

# ======================================================================
# Generate the HTML file
# ======================================================================
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>HADR Implementation Checklist</title>
<style>
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root {
    --primary: #1a73e8; --primary-dark: #1557b0; --success: #1e8e3e; --warning: #f9ab00;
    --danger: #d93025; --bg: #f8f9fa; --card-bg: #fff; --text: #202124; --text-secondary: #5f6368;
    --border: #dadce0; --sidebar-bg: #1e293b; --sidebar-text: #cbd5e1; --sidebar-active: #1a73e8;
    --radius: 8px; --shadow: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08);
}
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif; background: var(--bg); color: var(--text); display: flex; min-height: 100vh; line-height: 1.5; }
.sidebar {
    width: 280px; background: var(--sidebar-bg); color: var(--sidebar-text); padding: 20px 0;
    position: fixed; top: 0; left: 0; bottom: 0; overflow-y: auto; z-index: 100;
    display: flex; flex-direction: column;
}
.sidebar h2 { padding: 0 20px 16px; font-size: 16px; font-weight: 600; color: #f1f5f9; border-bottom: 1px solid #334155; }
.phase-nav { flex: 1; padding: 8px 0; }
.phase-nav-item {
    display: flex; align-items: center; padding: 10px 20px; cursor: pointer; transition: background 0.2s;
    border-left: 3px solid transparent; gap: 10px; font-size: 13px;
}
.phase-nav-item:hover { background: rgba(255,255,255,0.05); }
.phase-nav-item.active { background: rgba(26,115,232,0.15); border-left-color: var(--sidebar-active); color: #fff; }
.phase-dot {
    width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
    background: #475569; transition: background 0.3s;
}
.phase-dot.complete { background: var(--success); }
.phase-dot.partial { background: var(--warning); }
.phase-nav-label { flex: 1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.phase-nav-count { font-size: 11px; color: #64748b; flex-shrink: 0; }
.main { margin-left: 280px; flex: 1; padding: 30px 40px; max-width: 960px; }
.header { margin-bottom: 24px; }
.header h1 { font-size: 24px; font-weight: 600; color: var(--text); }
.header p { color: var(--text-secondary); font-size: 14px; margin-top: 4px; }
.progress-container {
    background: var(--card-bg); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 16px 20px; margin-bottom: 24px; box-shadow: var(--shadow);
}
.progress-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; font-size: 13px; }
.progress-bar-bg { height: 8px; background: #e8eaed; border-radius: 4px; overflow: hidden; }
.progress-bar-fill { height: 100%; background: linear-gradient(90deg, var(--primary), #4a90d9); border-radius: 4px; transition: width 0.5s ease; width: 0%; }
.progress-stats { display: flex; gap: 24px; margin-top: 8px; font-size: 12px; color: var(--text-secondary); }
.phase-card { display: none; }
.phase-card.active { display: block; }
.phase-title {
    font-size: 18px; font-weight: 600; margin-bottom: 4px; display: flex; align-items: center; gap: 10px;
}
.phase-desc { font-size: 13px; color: var(--text-secondary); margin-bottom: 16px; }
.step-item {
    background: var(--card-bg); border: 1px solid var(--border); border-radius: var(--radius);
    margin-bottom: 8px; box-shadow: var(--shadow); overflow: hidden; transition: border-color 0.2s;
}
.step-item:hover { border-color: #bbb; }
.step-header {
    display: flex; align-items: flex-start; padding: 14px 16px; cursor: pointer; gap: 12px;
    user-select: none;
}
.step-checkbox { margin-top: 2px; width: 18px; height: 18px; cursor: pointer; accent-color: var(--primary); flex-shrink: 0; }
.step-content { flex: 1; min-width: 0; }
.step-task { font-size: 14px; font-weight: 500; line-height: 1.4; }
.step-task.completed { text-decoration: line-through; color: var(--text-secondary); }
.step-meta { display: flex; gap: 6px; align-items: center; margin-top: 4px; flex-wrap: wrap; }
.badge {
    display: inline-block; padding: 1px 8px; border-radius: 10px; font-size: 10px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.3px;
}
.badge-required { background: #fce8e6; color: var(--danger); }
.badge-recommended { background: #fef7e0; color: #e37400; }
.badge-optional { background: #e8f0fe; color: var(--primary); }
.step-id { font-size: 11px; color: var(--text-secondary); font-family: 'Consolas', 'Courier New', monospace; }
.step-details {
    display: none; padding: 0 16px 14px 46px; font-size: 13px; color: var(--text-secondary);
    border-top: 1px solid var(--border); margin-top: 0;
}
.step-details.open { display: block; }
.step-details h4 { color: var(--text); font-size: 12px; font-weight: 600; margin: 10px 0 4px; text-transform: uppercase; letter-spacing: 0.5px; }
.step-details p { margin-bottom: 6px; }
.step-details code {
    display: block; background: #f1f3f4; padding: 8px 12px; border-radius: 4px; font-family: 'Consolas', 'Courier New', monospace;
    font-size: 12px; white-space: pre-wrap; word-break: break-all; margin-bottom: 6px; border: 1px solid #e8eaed;
}
.expand-icon { font-size: 10px; color: var(--text-secondary); transition: transform 0.2s; flex-shrink: 0; margin-top: 4px; }
.expand-icon.open { transform: rotate(90deg); }
.nav-buttons {
    display: flex; justify-content: space-between; margin-top: 24px; gap: 12px;
}
.btn {
    padding: 10px 24px; border: none; border-radius: var(--radius); font-size: 14px; font-weight: 500;
    cursor: pointer; transition: background 0.2s, box-shadow 0.2s;
}
.btn-primary { background: var(--primary); color: #fff; }
.btn-primary:hover { background: var(--primary-dark); box-shadow: 0 1px 3px rgba(26,115,232,0.3); }
.btn-primary:disabled { background: #c4c7c5; cursor: not-allowed; box-shadow: none; }
.btn-secondary { background: #fff; color: var(--text); border: 1px solid var(--border); }
.btn-secondary:hover { background: #f8f9fa; }
.btn-danger { background: var(--danger); color: #fff; }
.btn-danger:hover { background: #c5221f; }
.completion-banner {
    display: none; background: linear-gradient(135deg, #1e8e3e, #34a853); color: #fff; padding: 20px 24px;
    border-radius: var(--radius); margin-bottom: 24px; text-align: center; box-shadow: 0 2px 8px rgba(30,142,62,0.3);
}
.completion-banner.show { display: block; }
.completion-banner h2 { font-size: 20px; margin-bottom: 4px; }
.completion-banner p { font-size: 14px; opacity: 0.9; }
.top-actions { display: flex; gap: 8px; margin-bottom: 16px; justify-content: flex-end; }
@media (max-width: 768px) {
    .sidebar { width: 200px; }
    .main { margin-left: 200px; padding: 20px; }
}
@media (max-width: 600px) {
    body { flex-direction: column; }
    .sidebar { position: static; width: 100%; height: auto; max-height: 200px; padding: 10px 0; }
    .sidebar h2 { padding: 0 16px 10px; font-size: 14px; }
    .phase-nav-item { padding: 6px 16px; font-size: 12px; }
    .main { margin-left: 0; padding: 16px; }
    .nav-buttons { flex-direction: column; }
    .btn { width: 100%; text-align: center; }
}
</style>
</head>
<body>
<div class="sidebar">
    <h2>HADR Checklist</h2>
    <div class="phase-nav" id="phaseNav"></div>
    <div style="padding: 12px 20px; border-top: 1px solid #334155; font-size: 11px; color: #64748b;">
        <div id="totalProgress">0% complete</div>
        <div id="footerStats">0 / 0 steps</div>
    </div>
</div>
<div class="main">
    <div class="header">
        <h1>HADR Implementation Checklist</h1>
        <p>SQL Server Always On Availability Group deployment with $SecondaryReplicas secondary replica(s) | $($witnessDesc) | $DomainControllerCount Domain Controller(s)</p>
    </div>
    <div class="progress-container">
        <div class="progress-header">
            <span>Overall Progress</span>
            <span id="progressPercent">0%</span>
        </div>
        <div class="progress-bar-bg"><div class="progress-bar-fill" id="progressBar"></div></div>
        <div class="progress-stats">
            <span id="stepsDone">0</span> completed
            <span id="stepsLeft">0</span> remaining
            <span id="totalSteps">0</span> total
        </div>
    </div>
    <div class="completion-banner" id="completionBanner">
        <h2>All Steps Complete</h2>
        <p>HADR implementation checklist has been fully completed.</p>
    </div>
    <div class="top-actions">
        <button class="btn btn-danger" onclick="resetProgress()">Reset Progress</button>
    </div>
    <div id="phaseContainer"></div>
    <div class="nav-buttons">
        <button class="btn btn-secondary" id="prevBtn" onclick="navigate(-1)">Previous</button>
        <button class="btn btn-primary" id="nextBtn" onclick="navigate(1)">Next</button>
    </div>
</div>
<script id="steps-data" type="application/json">
$stepsJson
</script>
<script>
var stepsData = JSON.parse(document.getElementById('steps-data').textContent);
var phases = {};
var phaseOrder = [];
stepsData.forEach(function(s) {
    if (!phases[s.PhaseID]) { phases[s.PhaseID] = { id: s.PhaseID, name: s.PhaseName, steps: [] }; phaseOrder.push(s.PhaseID); }
    phases[s.PhaseID].steps.push(s);
});
var currentPhase = 0;
function saveProgress() {
    var state = {};
    stepsData.forEach(function(s) { state[s.StepID] = s.Status; });
    localStorage.setItem('hadr-checklist', JSON.stringify(state));
}
function loadProgress() {
    var saved = localStorage.getItem('hadr-checklist');
    if (!saved) return;
    try {
        var state = JSON.parse(saved);
        stepsData.forEach(function(s) {
            if (state[s.StepID]) s.Status = state[s.StepID];
        });
    } catch(e) {}
}
function updateAll() {
    updateProgress();
    renderSidebar();
    renderCurrentPhase();
    updateNavButtons();
    renderTotalProgress();
}
function updateProgress() {
    var total = stepsData.length;
    var done = stepsData.filter(function(s) { return s.Status === 'Completed'; }).length;
    var pct = total > 0 ? Math.round(done / total * 100) : 0;
    document.getElementById('progressBar').style.width = pct + '%';
    document.getElementById('progressPercent').textContent = pct + '%';
    document.getElementById('stepsDone').textContent = done;
    document.getElementById('stepsLeft').textContent = total - done;
    document.getElementById('totalSteps').textContent = total;
    document.getElementById('totalProgress').textContent = pct + '% complete';
    document.getElementById('footerStats').textContent = done + ' / ' + total + ' steps';
    var banner = document.getElementById('completionBanner');
    if (done === total && total > 0) { banner.classList.add('show'); } else { banner.classList.remove('show'); }
}
function renderTotalProgress() {
    phaseOrder.forEach(function(pid) {
        var ph = phases[pid];
        var total = ph.steps.length;
        var done = ph.steps.filter(function(s) { return s.Status === 'Completed'; }).length;
        var el = document.getElementById('nav-' + pid.replace(/\s+/g, ''));
        if (el) {
            var dot = el.querySelector('.phase-dot');
            dot.className = 'phase-dot';
            if (done === total && total > 0) dot.classList.add('complete');
            else if (done > 0) dot.classList.add('partial');
            el.querySelector('.phase-nav-count').textContent = done + '/' + total;
        }
    });
}
function renderSidebar() {
    var nav = document.getElementById('phaseNav');
    nav.innerHTML = '';
    phaseOrder.forEach(function(pid, idx) {
        var ph = phases[pid];
        var total = ph.steps.length;
        var done = ph.steps.filter(function(s) { return s.Status === 'Completed'; }).length;
        var div = document.createElement('div');
        div.className = 'phase-nav-item' + (idx === currentPhase ? ' active' : '');
        div.id = 'nav-' + pid.replace(/\s+/g, '');
        var dot = document.createElement('span');
        dot.className = 'phase-dot';
        if (done === total && total > 0) dot.classList.add('complete');
        else if (done > 0) dot.classList.add('partial');
        var label = document.createElement('span');
        label.className = 'phase-nav-label';
        label.textContent = ph.name;
        var count = document.createElement('span');
        count.className = 'phase-nav-count';
        count.textContent = done + '/' + total;
        div.appendChild(dot);
        div.appendChild(label);
        div.appendChild(count);
        div.addEventListener('click', function() { currentPhase = idx; updateAll(); });
        nav.appendChild(div);
    });
}
function renderCurrentPhase() {
    var container = document.getElementById('phaseContainer');
    var pid = phaseOrder[currentPhase];
    var ph = phases[pid];
    var html = '<div class="phase-card active">';
    html += '<div class="phase-title">' + ph.name + '</div>';
    html += '<div class="phase-desc">Phase ' + (currentPhase + 1) + ' of ' + phaseOrder.length + '</div>';
    ph.steps.forEach(function(s) {
        var checked = s.Status === 'Completed' ? 'checked' : '';
        var taskClass = s.Status === 'Completed' ? 'completed' : '';
        html += '<div class="step-item">';
        html += '<div class="step-header" onclick="toggleStep(this)">';
        html += '<input type="checkbox" class="step-checkbox" ' + checked + ' onclick="event.stopPropagation(); toggleCheck(this)" data-stepid="' + s.StepID + '">';
        html += '<div class="step-content">';
        html += '<div class="step-task ' + taskClass + '">' + escapeHtml(s.Task) + '</div>';
        html += '<div class="step-meta">';
        html += '<span class="step-id">' + s.StepID + '</span>';
        html += '<span class="badge badge-' + s.Severity.toLowerCase() + '">' + s.Severity + '</span>';
        if (s.EstMinutes) html += '<span style="font-size:11px;color:#5f6368">~' + s.EstMinutes + ' min</span>';
        html += '</div></div>';
        html += '<span class="expand-icon">></span>';
        html += '</div>';
        html += '<div class="step-details">';
        if (s.Details) html += '<h4>Description</h4><p>' + escapeHtml(s.Details) + '</p>';
        if (s.Command && s.Command !== 'No command - conceptual understanding' && s.Command !== 'No command - explanation') {
            html += '<h4>Command</h4><code>' + escapeHtml(s.Command) + '</code>';
        }
        if (s.ExpectedResult) html += '<h4>Expected Result</h4><p>' + escapeHtml(s.ExpectedResult) + '</p>';
        if (s.WhyThisMatters) html += '<h4>Why This Matters</h4><p>' + escapeHtml(s.WhyThisMatters) + '</p>';
        if (s.Prerequisite && s.Prerequisite !== 'None') html += '<h4>Prerequisites</h4><p>' + escapeHtml(s.Prerequisite) + '</p>';
        if (s.VerificationMethod) html += '<h4>Verification</h4><p>' + escapeHtml(s.VerificationMethod) + '</p>';
        html += '</div></div>';
    });
    html += '</div>';
    container.innerHTML = html;
}
function escapeHtml(str) {
    if (!str) return '';
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
}
function toggleStep(header) {
    var details = header.nextElementSibling;
    var icon = header.querySelector('.expand-icon');
    if (details) { details.classList.toggle('open'); }
    if (icon) { icon.classList.toggle('open'); }
}
function toggleCheck(cb) {
    var stepId = cb.getAttribute('data-stepid');
    stepsData.forEach(function(s) {
        if (s.StepID === stepId) {
            s.Status = cb.checked ? 'Completed' : 'Not Started';
        }
    });
    saveProgress();
    updateAll();
}
function navigate(dir) {
    var newIdx = currentPhase + dir;
    if (newIdx < 0 || newIdx >= phaseOrder.length) return;
    currentPhase = newIdx;
    updateAll();
    document.querySelector('.main').scrollTop = 0;
    window.scrollTo(0, 0);
}
function updateNavButtons() {
    document.getElementById('prevBtn').disabled = currentPhase === 0;
    document.getElementById('nextBtn').disabled = currentPhase === phaseOrder.length - 1;
}
function resetProgress() {
    if (!confirm('Reset all progress? This cannot be undone.')) return;
    stepsData.forEach(function(s) { s.Status = 'Not Started'; });
    localStorage.removeItem('hadr-checklist');
    updateAll();
}
loadProgress();
updateAll();
</script>
</body>
</html>
"@

$outputDir = Split-Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

$html | Out-File -FilePath $OutputPath -Encoding utf8

Write-Host "HADR Checklist generated: $OutputPath"
Write-Host "Total steps: $($steps.Count)"
Write-Host "Total phases: $($phasesList.Count)"
