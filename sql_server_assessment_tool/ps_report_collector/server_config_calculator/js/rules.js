/**
 * Predefined application-type rules and sizing formulas.
 * Used by the Server Sizing Estimator to recommend CPU, RAM, storage, network, HADR.
 */
window.ServerConfigRules = (() => {
  /** @typedef {'small'|'mid'|'large'|'xlarge'} Tier */

  const APP_TYPES = {
    oltp: {
      id: 'oltp',
      label: 'OLTP / Transactional',
      description: 'High concurrency, short transactions, frequent reads/writes (ERP, booking, banking).',
      cpuWeight: 1.2,
      ramWeight: 1.1,
      storageWeight: 1.0,
      iopsWeight: 1.4,
      networkWeight: 1.0,
      hadrBias: 'high',
      storageProfile: 'ssd_premium',
      notes: [
        'Prioritize low-latency SSD and enough RAM for buffer cache.',
        'Keep MaxDOP moderate (OLTP-friendly) after sizing hardware.',
        'Plan HADR (AG / streaming replication) for RPO near zero.',
      ],
    },
    ecommerce: {
      id: 'ecommerce',
      label: 'E-commerce / Retail',
      description: 'Bursty traffic, catalog reads, order writes, seasonal peaks.',
      cpuWeight: 1.3,
      ramWeight: 1.2,
      storageWeight: 1.1,
      iopsWeight: 1.3,
      networkWeight: 1.4,
      hadrBias: 'high',
      storageProfile: 'ssd_premium',
      notes: [
        'Size for peak (events/sales), not average daily load.',
        'Separate read replicas for catalog/search if traffic grows.',
        'Network bandwidth matters for CDN + API + checkout spikes.',
      ],
    },
    saas: {
      id: 'saas',
      label: 'SaaS / Multi-tenant',
      description: 'Many tenants, mixed workloads, growth-oriented concurrency.',
      cpuWeight: 1.25,
      ramWeight: 1.3,
      storageWeight: 1.2,
      iopsWeight: 1.25,
      networkWeight: 1.2,
      hadrBias: 'high',
      storageProfile: 'ssd_premium',
      notes: [
        'RAM grows with tenant count and connection pooling needs.',
        'Prefer connection poolers (PgBouncer / RDS Proxy / etc.).',
        'HADR and backups are critical for multi-tenant SLAs.',
      ],
    },
    reporting: {
      id: 'reporting',
      label: 'Reporting / Analytics',
      description: 'Heavy reads, large scans, periodic ETL into warehouse-style schemas.',
      cpuWeight: 1.4,
      ramWeight: 1.5,
      storageWeight: 1.6,
      iopsWeight: 1.1,
      networkWeight: 1.1,
      hadrBias: 'medium',
      storageProfile: 'ssd_throughput',
      notes: [
        'More CPU/RAM for parallel query; storage capacity dominates.',
        'Consider columnstore / partitioning for large fact tables.',
        'HADR can be async / delayed replica to protect primary OLTP.',
      ],
    },
    mixed: {
      id: 'mixed',
      label: 'Mixed OLTP + Reporting',
      description: 'Same database serves transactions and operational reports.',
      cpuWeight: 1.35,
      ramWeight: 1.35,
      storageWeight: 1.3,
      iopsWeight: 1.35,
      networkWeight: 1.15,
      hadrBias: 'high',
      storageProfile: 'ssd_premium',
      notes: [
        'Isolate reporting via replicas when possible.',
        'Size primary for OLTP peaks; replica for heavy reads.',
        'Watch tempdb / work_mem under concurrent analytical queries.',
      ],
    },
    iot: {
      id: 'iot',
      label: 'IoT / Telemetry / Logging',
      description: 'High insert rate, append-heavy, time-series retention.',
      cpuWeight: 1.1,
      ramWeight: 1.0,
      storageWeight: 1.8,
      iopsWeight: 1.5,
      networkWeight: 1.3,
      hadrBias: 'medium',
      storageProfile: 'ssd_throughput',
      notes: [
        'Storage growth and ingest IOPS dominate sizing.',
        'Partition by time; define retention/archival early.',
        'Async replicas or object-storage archival often enough for DR.',
      ],
    },
    cms: {
      id: 'cms',
      label: 'CMS / Content Platform',
      description: 'Read-heavy content, moderate writes, media metadata.',
      cpuWeight: 0.9,
      ramWeight: 1.0,
      storageWeight: 1.2,
      iopsWeight: 0.9,
      networkWeight: 1.1,
      hadrBias: 'medium',
      storageProfile: 'ssd_standard',
      notes: [
        'Cache layers (CDN/Redis) reduce DB load significantly.',
        'DB mainly stores metadata; media often offloaded to object storage.',
        'Mid-tier often sufficient unless editorial concurrency is high.',
      ],
    },
    batch: {
      id: 'batch',
      label: 'Batch / ETL / Integration',
      description: 'Scheduled bulk loads, transformations, overnight jobs.',
      cpuWeight: 1.3,
      ramWeight: 1.2,
      storageWeight: 1.5,
      iopsWeight: 1.4,
      networkWeight: 1.2,
      hadrBias: 'low',
      storageProfile: 'ssd_throughput',
      notes: [
        'Size for job windows (CPU + sequential/throughput disk).',
        'Staging + target storage must both be accounted for.',
        'HADR optional if jobs are restartable and backups are solid.',
      ],
    },
  };

  const TIER_SPECS = {
    small: {
      label: 'Small',
      vcpu: 4,
      ramGb: 16,
      storageGb: 250,
      networkMbps: 500,
      description: 'Dev/test, light production, low concurrency.',
    },
    mid: {
      label: 'Mid',
      vcpu: 8,
      ramGb: 64,
      storageGb: 1000,
      networkMbps: 2000,
      description: 'Typical production OLTP / mid SaaS.',
    },
    large: {
      label: 'Large',
      vcpu: 16,
      ramGb: 128,
      storageGb: 4000,
      networkMbps: 5000,
      description: 'High concurrency or heavy analytics.',
    },
    xlarge: {
      label: 'X-Large',
      vcpu: 32,
      ramGb: 256,
      storageGb: 10000,
      networkMbps: 10000,
      description: 'Enterprise / peak seasonal / large telemetry.',
    },
  };

  const STORAGE_PROFILES = {
    ssd_standard: { label: 'SSD (General Purpose)', iopsHint: '3k–10k IOPS', latency: 'low' },
    ssd_premium: { label: 'Premium SSD / NVMe', iopsHint: '10k–40k+ IOPS', latency: 'very low' },
    ssd_throughput: { label: 'Throughput-optimized SSD', iopsHint: 'high sequential MB/s', latency: 'low' },
    hdd: { label: 'HDD (not recommended for DB)', iopsHint: '<500 IOPS', latency: 'high' },
  };

  /**
   * Score workload intensity 0–100 from application flow inputs.
   */
  function computeWorkloadScore(input, app) {
    const users = Number(input.users) || 0;
    const concurrent = Number(input.concurrentUsers) || Math.max(1, Math.ceil(users * 0.1));
    const tables = Number(input.tables) || 0;
    const dailyInsertRows = Number(input.dailyInsertRows) || 0;
    const dailyInsertGb = Number(input.dailyInsertGb) || 0;
    const weeklyGb = Number(input.weeklyInsertGb) || dailyInsertGb * 7;
    const monthlyGb = Number(input.monthlyInsertGb) || weeklyGb * 4.3;

    // Normalized component scores (soft caps)
    const userScore = Math.min(40, concurrent / 25); // 1000 concurrent ~ 40
    const insertRowScore = Math.min(25, dailyInsertRows / 200000); // 5M rows/day ~ 25
    const volumeScore = Math.min(25, monthlyGb / 40); // ~1TB/month ~ 25
    const tableScore = Math.min(10, tables / 50); // 500 tables ~ 10

    const raw =
      (userScore + insertRowScore + volumeScore + tableScore) *
      ((app.cpuWeight + app.ramWeight + app.storageWeight + app.iopsWeight) / 4);

    return {
      score: Math.min(100, Math.round(raw * 2.2)),
      concurrent,
      dailyInsertRows,
      dailyInsertGb,
      weeklyGb,
      monthlyGb,
      components: { userScore, insertRowScore, volumeScore, tableScore },
    };
  }

  function pickTier(score) {
    if (score < 20) return 'small';
    if (score < 45) return 'mid';
    if (score < 70) return 'large';
    return 'xlarge';
  }

  function recommendHadr(app, input, tier) {
    const criticality = input.criticality || 'medium'; // low | medium | high | mission
    const rpoMinutes = Number(input.rpoMinutes);
    const bias = app.hadrBias;

    let level = 'None / backups only';
    let detail = 'Nightly full + frequent log/WAL backups may be enough.';

    const forceHigh =
      criticality === 'mission' ||
      criticality === 'high' ||
      bias === 'high' ||
      tier === 'xlarge' ||
      (!Number.isNaN(rpoMinutes) && rpoMinutes <= 15);

    const forceMedium =
      bias === 'medium' || criticality === 'medium' || tier === 'large';

    if (forceHigh) {
      level = 'High (sync/near-sync HADR)';
      detail =
        'SQL Server: Always On AG (sync + async DR). PostgreSQL: primary + sync standby + async DR, or managed HA.';
    } else if (forceMedium || bias !== 'low') {
      level = 'Medium (async replica + backups)';
      detail =
        'Async readable replica for failover/reporting, plus PITR backups. RPO typically minutes.';
    } else if (criticality === 'low' && bias === 'low') {
      level = 'Low (backups + restartable jobs)';
      detail = 'Reliable backups and tested restore runbooks; replica optional.';
    }

    return { level, detail };
  }

  function recommendNetwork(tier, app, concurrent) {
    const base = TIER_SPECS[tier].networkMbps;
    const scaled = Math.round(base * app.networkWeight * (1 + Math.min(1, concurrent / 2000)));
    return {
      mbps: scaled,
      label: scaled >= 5000 ? '10 GbE class' : scaled >= 2000 ? '2–5 GbE class' : '1 GbE class',
    };
  }

  function recommendStorage(tier, app, monthlyGb) {
    const base = TIER_SPECS[tier].storageGb;
    // 12 months growth + 40% headroom + indexes/temp (~1.6x data)
    const projected = Math.ceil(monthlyGb * 12 * 1.6 * 1.4);
    const storageGb = Math.max(base, projected);
    const profile = STORAGE_PROFILES[app.storageProfile];
    return { storageGb, profile, projectedDataGb: Math.ceil(monthlyGb * 12) };
  }

  function recommendCpuRam(tier, app, score, concurrent) {
    const base = TIER_SPECS[tier];
    let vcpu = Math.ceil(base.vcpu * Math.min(1.5, app.cpuWeight));
    let ramGb = Math.ceil(base.ramGb * Math.min(1.6, app.ramWeight));

    // Soft bump for high concurrency
    if (concurrent >= 500) {
      vcpu = Math.max(vcpu, 16);
      ramGb = Math.max(ramGb, 128);
    }
    if (concurrent >= 1500 || score >= 80) {
      vcpu = Math.max(vcpu, 32);
      ramGb = Math.max(ramGb, 256);
    }

    // Snap to common cloud sizes
    const vcpuSteps = [2, 4, 8, 16, 32, 48, 64];
    const ramSteps = [8, 16, 32, 64, 128, 256, 384, 512];
    vcpu = vcpuSteps.find((n) => n >= vcpu) || vcpu;
    ramGb = ramSteps.find((n) => n >= ramGb) || ramGb;

    return { vcpu, ramGb };
  }

  function sizeServer(input) {
    const app = APP_TYPES[input.appType] || APP_TYPES.mixed;
    const workload = computeWorkloadScore(input, app);
    const tier = pickTier(workload.score);
    const { vcpu, ramGb } = recommendCpuRam(tier, app, workload.score, workload.concurrent);
    const storage = recommendStorage(tier, app, workload.monthlyGb);
    const network = recommendNetwork(tier, app, workload.concurrent);
    const hadr = recommendHadr(app, input, tier);
    const tierSpec = TIER_SPECS[tier];

    const engine = input.dbEngine || 'both';

    return {
      app,
      workload,
      tier,
      tierLabel: tierSpec.label,
      tierDescription: tierSpec.description,
      recommendation: {
        serverType: tierSpec.label,
        vcpu,
        ramGb,
        storageGb: storage.storageGb,
        storageType: storage.profile.label,
        storageIopsHint: storage.profile.iopsHint,
        networkMbps: network.mbps,
        networkLabel: network.label,
        hadrLevel: hadr.level,
        hadrDetail: hadr.detail,
        dbEngine: engine,
        projectedAnnualDataGb: storage.projectedDataGb,
      },
      rationale: [
        `Workload score ${workload.score}/100 → ${tierSpec.label} tier.`,
        `App type “${app.label}” applies CPU×${app.cpuWeight}, RAM×${app.ramWeight}, storage×${app.storageWeight}.`,
        `Assumed ~${workload.concurrent} concurrent users; ~${workload.monthlyGb} GB/month ingest.`,
        ...app.notes,
      ],
      formulas: {
        concurrentUsers: 'concurrent ≈ users × 10% (if not provided)',
        monthlyVolume: 'monthly GB ≈ weekly × 4.3 (if not provided)',
        storage: 'storage ≈ max(tier base, monthly×12×1.6 indexes/temp ×1.4 headroom)',
        score: 'score from concurrent users + daily rows + monthly GB + table count, weighted by app type',
      },
    };
  }

  return {
    APP_TYPES,
    TIER_SPECS,
    STORAGE_PROFILES,
    sizeServer,
    computeWorkloadScore,
    pickTier,
  };
})();
