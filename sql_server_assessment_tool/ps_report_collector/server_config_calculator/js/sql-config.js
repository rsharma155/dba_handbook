/**
 * SQL Server configuration recommendations from hardware inputs.
 * Best-practice oriented (OLTP-friendly defaults with workload overrides).
 */
window.SqlServerConfig = (() => {
  function osReserveGb(ramGb) {
    if (ramGb <= 16) return Math.max(2, Math.ceil(ramGb * 0.2));
    if (ramGb <= 64) return Math.max(4, Math.ceil(ramGb * 0.1));
    if (ramGb <= 256) return Math.max(8, Math.ceil(ramGb * 0.08));
    return Math.max(16, Math.ceil(ramGb * 0.06));
  }

  function recommendMaxDop(vcpu, numaNodes, workload) {
    const nodes = Math.max(1, numaNodes || 1);
    const coresPerNuma = Math.max(1, Math.floor(vcpu / nodes));
    // Common guidance: keep MAXDOP <= 8 and <= cores per NUMA
    let maxDop = Math.min(8, coresPerNuma);
    if (workload === 'oltp') maxDop = Math.min(4, maxDop);
    if (workload === 'reporting' || workload === 'mixed') maxDop = Math.min(8, coresPerNuma);
    if (vcpu <= 2) maxDop = 1;
    return Math.max(1, maxDop);
  }

  function tempdbFiles(vcpu) {
    // Microsoft guidance: start with 4–8, up to logical cores, capped at 8 initially
    if (vcpu <= 4) return vcpu;
    return Math.min(8, vcpu);
  }

  function recommend(input) {
    const vcpu = Math.max(1, Number(input.vcpu) || 4);
    const ramGb = Math.max(1, Number(input.ramGb) || 16);
    const storageType = input.storageType || 'ssd';
    const cpuType = input.cpuType || 'general'; // general | compute | memory
    const numaNodes = Math.max(1, Number(input.numaNodes) || 1);
    const workload = input.workload || 'oltp';
    const storageGb = Math.max(1, Number(input.storageGb) || 250);

    const reserve = osReserveGb(ramGb);
    const maxServerMemoryMb = Math.max(1024, (ramGb - reserve) * 1024);
    const minServerMemoryMb = Math.min(
      Math.round(maxServerMemoryMb * 0.25),
      Math.round(ramGb * 0.15 * 1024)
    );
    const maxDop = recommendMaxDop(vcpu, numaNodes, workload);
    const costThreshold = workload === 'oltp' ? 50 : workload === 'reporting' ? 25 : 40;
    const tempdb = tempdbFiles(vcpu);

    const optimizeForAdHoc = workload === 'oltp' || workload === 'mixed';
    const backupCompression = true;

    const settings = [
      {
        name: 'max server memory (MB)',
        value: maxServerMemoryMb,
        why: `Leave ~${reserve} GB for OS / agents / AV. Formula: (RAM − OS reserve) × 1024.`,
      },
      {
        name: 'min server memory (MB)',
        value: minServerMemoryMb,
        why: 'Avoid extreme memory shrink under pressure; ~15–25% of max server memory.',
      },
      {
        name: 'max degree of parallelism',
        value: maxDop,
        why: `NUMA-aware: min(8, cores/NUMA${workload === 'oltp' ? ', 4 for OLTP' : ''}). vCPU=${vcpu}, NUMA=${numaNodes}.`,
      },
      {
        name: 'cost threshold for parallelism',
        value: costThreshold,
        why: 'Default 5 is too low; raise to reduce CXPACKET noise on OLTP.',
      },
      {
        name: 'optimize for ad hoc workloads',
        value: optimizeForAdHoc ? 1 : 0,
        why: 'Reduces plan-cache bloat from one-off queries (common in apps/ORMs).',
      },
      {
        name: 'backup compression default',
        value: backupCompression ? 1 : 0,
        why: 'Smaller/faster backups on modern CPUs; standard best practice.',
      },
      {
        name: 'remote query timeout (s)',
        value: 600,
        why: 'Safer default than unlimited for linked-server / remote calls.',
      },
      {
        name: 'tempdb data files',
        value: tempdb,
        why: 'One file per logical CPU up to 8 to reduce PFS/GAM/SGAM contention.',
      },
      {
        name: 'tempdb initial size / autogrowth',
        value: `Equal-sized files; fixed MB growth (e.g. 512–1024 MB), not %`,
        why: 'Pre-size to avoid runtime growth storms.',
      },
      {
        name: 'instant file initialization',
        value: 'Enabled (Perform Volume Maintenance Tasks)',
        why: 'Fast data-file growth/restores; does not apply to log files.',
      },
    ];

    if (storageType === 'hdd') {
      settings.push({
        name: 'storage warning',
        value: 'HDD detected — migrate to SSD/NVMe for data + tempdb + log',
        why: 'Random I/O latency on HDD will dominate waits (PAGEIOLATCH).',
      });
    } else if (storageType === 'nvme' || storageType === 'ssd') {
      settings.push({
        name: 'data / log placement',
        value: 'Separate volumes when possible; both on SSD/NVMe',
        why: 'Isolates log sequential writes from data random I/O.',
      });
    }

    const instanceHints = [
      `CPU type “${cpuType}”: ${cpuType === 'memory' ? 'favor larger buffer pool / columnstore' : cpuType === 'compute' ? 'good for parallel reporting' : 'balanced general-purpose'}.`,
      `Lock pages in memory: consider for dedicated SQL boxes (service account right) when RAM ≥ 32 GB.`,
      `max worker threads: leave 0 (default) unless you have a measured worker shortage.`,
      `For Always On: size network for redo + backup traffic; keep sync commit replicas close.`,
      `Storage ~${storageGb} GB: plan ~20% free on data volumes; monitor autogrowth & VLFs.`,
    ];

    const tsql = buildTsql({
      maxServerMemoryMb,
      minServerMemoryMb,
      maxDop,
      costThreshold,
      optimizeForAdHoc,
      tempdb,
    });

    return {
      engine: 'SQL Server',
      summary: {
        vcpu,
        ramGb,
        osReserveGb: reserve,
        maxServerMemoryMb,
        maxDop,
        tempdbFiles: tempdb,
        storageType,
        workload,
      },
      settings,
      instanceHints,
      tsql,
    };
  }

  function buildTsql(p) {
    return `-- Recommended starter sp_configure (review before applying)
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', ${p.maxServerMemoryMb};
EXEC sp_configure 'min server memory (MB)', ${p.minServerMemoryMb};
EXEC sp_configure 'max degree of parallelism', ${p.maxDop};
EXEC sp_configure 'cost threshold for parallelism', ${p.costThreshold};
EXEC sp_configure 'optimize for ad hoc workloads', ${p.optimizeForAdHoc ? 1 : 0};
EXEC sp_configure 'backup compression default', 1;
RECONFIGURE;
-- Tempdb: use ${p.tempdb} equal-sized data files, pre-size, fixed MB growth (not %).`;
  }

  return { recommend, osReserveGb, recommendMaxDop };
})();
