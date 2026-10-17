# 09. Explore long-term retention for an allowlist of series

Status: resolved
Type: research
Repo: homelab
Source: maintainer request 2026-09-26 (copyparty/03 retention decision)

## Problem

`retention.metric_days` is 14 and single-node VictoriaMetrics has one global retention. Some series
are worth keeping for years at low volume, such as car trips (copyparty/03), finance_exporter
tickers, disk usage trends and backup success timestamps. Raising the global retention would keep
all ~35 self-monitoring rule inputs and every node_exporter series for years too.

## Options to evaluate

1. **Second VictoriaMetrics instance** (`victoriametrics-lt` on secsvcs, long `--retentionPeriod`),
   fed only with allowlisted series:
   - vmagent: a second `-remoteWrite.url` with per-URL `-remoteWrite.urlRelabelConfig` keeping only
     `__name__=~"car_.*|finance_.*|..."`;
   - direct imports: copyparty/03 writes car data straight to it.

   Grafana gets a second datasource.
2. **Downsampling.** `-downsampling.period` is VictoriaMetrics Enterprise only. Check whether that
   is still true, and whether stream aggregation (`-streamAggr.config` on vmagent, e.g. 1h averages)
   can produce low-resolution copies for the long-term instance instead.
3. **Raise global retention.** Size it: current `vm_data_size_bytes` × (N days / 14), against the
   free disk on secsvcs.

## Deliverable

- A recommendation with a disk estimate per option, and the allowlist (metric name regex) as a
  `vars.yml` key (`retention.long_term_allowlist`), so adding a series is one line.
- Interaction with backups: the long-term instance's data directory needs to be in the
  backup-and-dr/09 inventory, since it becomes data that can't be recreated.
- Whether car data should be re-imported from the copyparty CSV archive once this lands (backfill
  script).

## Answer

**Recommendation: option 1, but fed by federation instead of vmagent.** Add a second
single-node VictoriaMetrics, `victoriametrics-lt`, on secsvcs:

- **Retention:** `--retentionPeriod=10y`.
- **Deduplication:** `--dedup.minScrapeInterval=1ms`.
- **Feed:** its own `-promscrape.config` holds one job. Every 5 minutes it scrapes the
  main instance's `/federate`, with `match[]` built from `retention.long_term_allowlist`.
  Each scrape stores the latest raw sample of every allowlisted series, which works out
  to last-value downsampling at 5 m.
- **Car data:** copyparty/03 POSTs car trips directly to this instance.

Downsampling and per-series retention both stay Enterprise-only. Raising the global
retention costs tens of GB per year on pve1's shared 500 GB NVMe, where the long-term
instance costs tens of MB.

Why federation and not a second `-remoteWrite.url`: vmagent only carries part of the
data.

- **Series vmagent never sees:**
  - pve1's `homelab_backup_*` textfile metrics and the secsvcs and pve1 filesystem
    series. The main VictoriaMetrics scrapes these itself (`src/secsvcs/prometheus.yml.j2`;
    the vmagent template says "On secsvcs just use VictoriaMetrics",
    `src/victoriametrics/vmagent.container.j2.j2`).
  - Telegraf on pfSense, which remote-writes directly (`docs/services.md` observability
    diagram).
- **Cost of the vmagent route:** a vmagent on secsvcs, plus a second URL and a relabel
  file on every vmagent (homesvcs, websvcs, and the VPS in observability/08).
- **Cost of federation:** one scrape job in one file, and it sees every ingestion path.

### Options

Allowlisted volume is estimated from the repo's exporters at about 210 series excluding
car data:

- `finance_*`: up to 24 metrics per Yahoo ticker and 2 per FRED series or Treasury tenor;
  about 110 series for 3 stocks, 12 FRED series and 12 tenors (`ticker` in `vars.yml`,
  `src/services/finance_exporter/config.yaml.j2`).
- Filesystem series: about 40 non-tmpfs mounts × 2 metrics across 5–6 node_exporters.
- About 20 `homelab_*` and `car_ingest_*` series.

Disk is estimated at about 1 B/sample, the docs' average: "sample size requires less or
around **1 byte** after compression"
(<https://docs.victoriametrics.com/guides/understand-your-setup-size/>).

| Option | Feeds | Resolution in LT | Disk (allowlist excl. car) | Covers secsvcs-scraped + Telegraf series | Verdict |
| --- | --- | --- | --- | --- | --- |
| **1a. LT instance, federation from main VM (5 m)** | 1 scrape job in the LT instance's own config | 5 m, last value | 150 × 288/day ≈ 16 MB/yr, **≈ 160 MB / 10 y** | yes | **do** |
| 1b. LT instance, 2nd `-remoteWrite.url` + `urlRelabelConfig` | every vmagent | raw 10 s | 150 × 8640/day ≈ 0.5 GB/yr (upper bound; flat gauges compress far below 1 B) | no (needs a vmagent on secsvcs) | no |
| 1c. 1b + per-URL stream aggregation, `interval: 1h` | every vmagent | 1 h | ≈ 1.3 MB/yr | no | no: renames series, drops partial hours, more config |
| 2. `-downsampling.period` | n/a | n/a | n/a | n/a | Enterprise only |
| 2′. `-retentionFilter` (per-series retention) | n/a | n/a | n/a | n/a | Enterprise only |
| 3. Raise global `retention.metric_days` | none | raw 10 s, all series | ≈ `sum(vm_data_size_bytes)` × N/14; at an assumed 15k active series ≈ 47 GB/yr raw, ×1.25 headroom ≈ **60 GB/yr, ≈ 300 GB / 5 y** | yes | no: pve1 has 500 GB total for router, secsvcs and homesvcs (`docs/architecture.md`) |

Car data comes on top of every row. Assume 20 PIDs at 1 Hz and 1 h of driving per day:
about 26 M samples/yr, roughly 26–100 MB/yr, since noisy sensor floats compress worse
than 1 B. Replace the assumption once copyparty/02's sample lands.

### Findings by question

#### 1. Second instance, vmagent and imports

- **Per-URL relabel is matched by position.** "the first `-remoteWrite.urlRelabelConfig`
  will be applied to the first `-remoteWrite.url`, and so on"
  (<https://docs.victoriametrics.com/victoriametrics/vmagent/#splitting-data-streams-among-multiple-systems>).
  - An empty value means no relabeling for that URL.
  - URLs past the last config get none.
  - More configs than URLs is a startup error ("mustn't exceed the number of
    -remoteWrite.url args", <https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/app/vmagent/remotewrite/relabel.go>).
- **Per-URL array flags have a trap.** If you pass one value, it applies to every URL:
  `GetOptionalArg` returns `x[0]` for every index
  (<https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/lib/flagutil/array.go>).
  - This covers `-remoteWrite.streamAggr.config` and `-remoteWrite.maxDiskUsagePerURL`.
  - `urlRelabelConfig` is the exception.
- **Pipeline order:**
  1. global `-remoteWrite.relabelConfig`;
  2. global `-streamAggr.config`;
  3. fan-out to each URL;
  4. per-URL `urlRelabelConfig`;
  5. per-URL `streamAggr.config`;
  6. per-URL queue.

  Source: <https://docs.victoriametrics.com/victoriametrics/vmagent/#life-of-a-sample>
- **Keep by name.** `action: keep_metrics` with `regex: 'a|b'` "Keeps metrics whose
  names match the `regex`". Regexes are anchored: they "must match the whole label name
  from start to end". VM's `if:` series selector also accepts `{fstype!="tmpfs"}`-style
  filters (<https://docs.victoriametrics.com/victoriametrics/relabeling/>).
- **Each URL gets its own queue.** "Each remote write URL corresponds to a folder similar
  to `1_B9EB7BE220B91E9D`" (flag position + URL hash). `-remoteWrite.maxDiskUsagePerURL`
  is per URL, and the oldest data is dropped past it. With the default disk queue, a down
  URL doesn't block the others
  (<https://docs.victoriametrics.com/victoriametrics/vmagent/#on-disk-persistence>).
  Reordering URLs orphans a queue.
- **Import endpoints**
  (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/>):
  - `/api/v1/import`: JSON lines, `"timestamps"` in ms.
  - `/api/v1/import/csv?format=1:time:unix_s,2:metric:speed,3:label:trip`; time types are
    `unix_s|unix_ms|unix_ns|rfc3339|custom:<layout>`.
  - `/api/v1/import/prometheus`: `<metric> <value> <ts_ms>`.
  - Parse errors may not reach the client. Watch `vm_rows_invalid_total`.
- **Old timestamps.** Samples older than now − `-retentionPeriod`, or older than
  `-maxBackfillAge` if set, are silently dropped and counted in
  `vm_rows_ignored_total{reason="small_timestamp"}`
  (<https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/lib/storage/storage.go>,
  <https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/app/vmstorage/main.go>).
  - Hard floor: 1970-01-02.
  - Future limit: now + 2 d (`-futureRetention`).
  - Backfill caveat: use `-search.disableCache`, or call `/internal/resetRollupResultCache`
    after the import. Single-node "automatically resets response cache when samples with
    timestamps older than `now - search.cacheTimestampOffset` are ingested"
    (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#backfilling>).
  - copyparty/03's 14-day `too_old` limit therefore becomes 10 years once car data goes
    to the long-term instance.
- **Federation.**
  - "the last point on the interval `[now - max_lookback ... now]` is scraped for each
    time series", with a default of `5m`
    (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#federation>).
  - `-search.maxFederateSeries` defaults to 1,000,000.
  - Scrape side: `metrics_path: /federate`, `honor_labels: true` and `params: {'match[]': ...}`
    (<https://prometheus.io/docs/prometheus/latest/federation/>).
  - VictoriaMetrics defaults `honor_timestamps` to false
    (<https://docs.victoriametrics.com/victoriametrics/sd_configs/>), so set it to true or
    every sample is re-stamped with scrape time.
  - Lookback in the long-term instance adapts to 5 m samples: `-search.maxLookback` "is
    dynamically detected from interval between time series datapoints"
    (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#list-of-command-line-flags>).
  - **Gap:** federation sees only the latest point at each scrape. After an outage longer
    than 5 m, data that vmagent's buffer backfills into the main instance never reaches
    the long-term instance. That's acceptable for trend series.

#### 2. Downsampling and stream aggregation

- **Still Enterprise-only** as of v1.153.0 (released 2026-09-28,
  <https://github.com/VictoriaMetrics/VictoriaMetrics/blob/master/docs/victoriametrics/changelog/CHANGELOG.md>).
  - "VictoriaMetrics Enterprise supports multi-level downsampling via
    `-downsampling.period=offset:interval`"
    (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#downsampling>).
  - The Enterprise feature list includes "Downsampling" and "Multiple retentions"
    (<https://docs.victoriametrics.com/victoriametrics/enterprise/>).
- **Stream aggregation** works in the community edition, but it's a poor fit here
  (<https://docs.victoriametrics.com/victoriametrics/stream-aggregation/configuration/>,
  <https://docs.victoriametrics.com/victoriametrics/stream-aggregation/>):
  - **Output names change** to `<metric>:<interval>[_by_..][_without_..]_<output>`, e.g.
    `finance_open_price:1h_last`. `keep_metric_names` allows only a single output, and it
    can't be combined with `keepInput`.
  - **Counters** need `total` or `increase` ("`avg` makes sense only for aggregating
    gauges").
  - **1 h intervals** flush "at the end of every hour". "The aggregated data on the first
    and the last interval is dropped during `vmagent` start, restart, or config reload"
    unless `flush_on_shutdown: true`. State is in memory. `AutoUpdate=registry` restarts
    therefore cost an hour.
  - **Input timestamps are ignored by default**: "processes samples based on their
    ingestion time". vmagent buffer replays after an outage collapse into the replay hour.
  - **Matched input is dropped and unmatched input is forwarded** by default. A per-URL
    config that should only affect URL #2 must pass an empty value for URL #1 (the
    single-value trap above).
  - Federation at 5 m gives last-value downsampling without any of these issues.

#### 3. Sizing a global retention raise

- **Measure live** (vmui on `metrics.SITE`):
  - `sum(vm_data_size_bytes)`;
  - bytes/sample:
    `sum(vm_data_size_bytes{type!~"indexdb.*"}) / sum(vm_rows{type!~"indexdb.*"})`, the
    expression `src/vmalert/configs/vmsingle.yml` already uses;
  - ingest rate: `sum(rate(vm_rows_added_to_storage_total[1d]))`.
- **Formula:** `Bytes Per Sample * Ingestion rate * Replication Factor *
  (Retention Period in Seconds +1 Retention Cycle) * 1.25`
  (<https://docs.victoriametrics.com/guides/understand-your-setup-size/>).
  - Keep "At least 20% of free storage space"
    (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#capacity-planning>).
  - `--storage.minFreeDiskSpaceBytes="8GiB"` stops ingestion before the disk is full
    (`src/victoriametrics/victoriametrics.container.j2`).
- **No disk sizes in the repo.** Neither the secsvcs disk size nor the active series count
  is in the repo. The only figures are pve1's 500 GB NVMe shared by three VMs
  (`docs/architecture.md`) and VictoriaLogs' 24 GiB cap
  (`src/victorialogs/victorialogs.container.j2`). Check on secsvcs with
  `df -h /var/lib/containers/storage/volumes`, and on pve1 with `lvs`.

#### 4. Granularity, Grafana, vmalert

- **`-retentionPeriod` units** are `h, d, w, M, y`; "If the time unit is not specified, a
  month (31 days) is assumed". "The minimum retention period is 24h or 1d", and there is
  no maximum ("e.g. `-retentionPeriod=100y`"). Disk peaks at retention + 1 month
  (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#retention>).
- **`-retentionFilter` is Enterprise-only.** "Community version of VictoriaMetrics
  supports only a single retention"
  (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#retention-filters>).
- **Grafana.** Add a second entry of the type the repo already uses
  (`victoriametrics-metrics-datasource`, `src/grafana/datasources.yml.j2`). The plugin's
  own example provisions two of that type
  (<https://github.com/VictoriaMetrics/victoriametrics-datasource>). Only one datasource
  may have `isDefault` (<https://grafana.com/docs/grafana/latest/administration/provisioning/#data-sources>).
- **vmalert.** No change. `-datasource.url` is a single string
  (<https://docs.victoriametrics.com/victoriametrics/vmalert/#flags>), and every alert
  (e.g. `BackupStale`) works on 14-day data. Alerting on long-term data would need a
  second vmalert; that's an inference, as the docs don't say.

### Proposed `vars.yml` keys

```yaml
retention:
  log_days: 14
  metric_days: 14
  hass_days: 14
  long_term_years: 10
  # Metric-name regexes kept for long_term_years in victoriametrics-lt, one per line.
  # They are joined with | and anchored. Car trip samples (car_<pid>) don't appear here:
  # car_ingest imports them straight into victoriametrics-lt.
  long_term_allowlist:
    - 'finance_.+'
    - 'node_filesystem_(size|avail)_bytes'
    - 'homelab_backup_last_success_timestamp_seconds'
    - 'homelab_snapraid_last_success_timestamp_seconds'
    - 'homelab_smart_healthy'
    - 'car_ingest_.+'
```

This renders to:
`finance_.+|node_filesystem_(size|avail)_bytes|homelab_backup_last_success_timestamp_seconds|homelab_snapraid_last_success_timestamp_seconds|homelab_smart_healthy|car_ingest_.+`.

Where the names come from:

- `homelab_backup_last_success_timestamp_seconds`: `src/pve1/backup_orchestrator.sh.j2`.
- `homelab_snapraid_last_success_timestamp_seconds` and `homelab_smart_healthy`:
  `src/snapraid/snapraid_run.sh.j2`, `src/vmalert/configs/backups.yml`.
- `node_filesystem_*`: `src/grafana/dashboards/node_exporter.json`.
- `car_ingest_*`: copyparty/03.

The pattern uses `car_ingest_.+`, not `car_.+`. If anything ever writes car samples to
the main instance too, federation won't copy them a second time.

### Config sketch

The long-term instance's scrape config is a new file next to `src/secsvcs/prometheus.yml.j2`:

```yaml
scrape_configs:
  - job_name: federate
    scrape_interval: 5m
    scrape_timeout: 1m
    metrics_path: /federate
    honor_labels: true
    honor_timestamps: true      # VM's default is false
    params:
      'match[]': ['{__name__=~"{{ retention.long_term_allowlist | join("|") }}"}']
    static_configs: [{targets: ['metrics.{{ site.url }}:8428']}]
    basic_auth: {username: admin, password: '%{VM_ADMIN_PASSWORD}'}
    metric_relabel_configs:     # node_exporter doesn't exclude tmpfs by default
      - if: '{__name__=~"node_filesystem_.+", fstype=~"tmpfs|ramfs"}'
        action: drop
```

node_exporter's `defFSTypesExcluded` doesn't list tmpfs
(<https://github.com/prometheus/node_exporter/blob/master/collector/filesystem_linux.go>).

The quadlet is a copy of `src/victoriametrics/victoriametrics.container.j2` with these
changes:

- `HostName=metrics-lt.SITE`, `IP=…10.10.0.16`. `.16` is the next free address; `.20` is
  fluent-bit.
- Volume `vmltdata`.
- `--retentionPeriod="{{ retention.long_term_years }}y"`.
- `--dedup.minScrapeInterval=1ms`. This makes copyparty/03 re-imports, and federation
  re-reads of unchanged samples, idempotent: "If multiple raw samples have the same
  timestamp ... the sample with the biggest value is kept"
  (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#deduplication>).
- `--memory.allowedBytes="128MiB"`.
- No `--vmalert.proxyURL`.

Wiring:

- **Inventory:** `src/nodes.yml` entry under secsvcs (subdomain `metrics-lt`, uptime check).
- **Ingress:** a Traefik route copied from `metrics.SITE` in
  `src/secsvcs/traefik/routes.yml.j2`, so `car_ingest` on websvcs can reach it.
- **Self-monitoring:** a `victoriametrics-lt` job in `src/secsvcs/prometheus.yml.j2`, so
  the existing `vmsingle.yml` disk alerts cover it.
- **Grafana:** a `VictoriaMetrics LT` datasource, not default. `car.json` uses it; the
  finance dashboard can switch to it for long ranges.

### Backups (backup-and-dr/09 inventory)

The long-term data can't be recreated, unlike `vmdata`, which `src/secsvcs/backup.sh.j2`
skips on purpose. secsvcs's VM image already reaches PBS (`src/pve1/backup.sh.j2`,
snapshot mode, images keep last 1, weekly 2, monthly 2 per `docs/services.md`), and the
storage survives an unclean stop: "storage never contains partially created parts, even
if hardware power off occurs"
(<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#storage>).
Image restores are all-or-nothing and age out within 2 months, though, so add a logical
dump:

- **In `src/secsvcs/backup.sh.j2`:**
  1. Run vmbackup:

     ```sh
     vmbackup -storageDataPath=/storage -snapshot.createURL=http://metrics-lt.SITE:8428/snapshot/create -dst=fs:///backup/vmlt
     ```

     (the `victoriametrics/vmbackup` image, with `vmltdata` and a scratch dir mounted). It
     creates and deletes the snapshot itself
     (<https://docs.victoriametrics.com/victoriametrics/vmbackup/>).
  2. `tar` the result into one file:
     `$(dump_dir victoriametrics-lt)/vmlt-<ts>.tar`.
- **Why vmbackup:** the docs say "Do not copy subdirectories inside
  `<-storageDataPath>/snapshot` with `cp`, `rsync`"
  (<https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#how-to-work-with-snapshots>).
- **Why one file:** the orchestrator's `pull()` handles dumps as single files
  (`-rm ${src}/dumps/*/*`, keep-newest by `find -maxdepth 1 -type f`,
  `src/pve1/backup_orchestrator.sh.j2`).
- **Retention:** the dump then lands in PBS namespace `files` (last 1, weekly 3,
  monthly 6) and through offsite (03).
- **Restore:** `vmrestore` into an emptied `vmltdata` with the container stopped.
- **Docs:**
  - list `vmltdata` in `docs/guides/pve1_recovery.md.j2`'s inventory and in
    `docs/guides/restore.md.j2`;
  - update `backup.sh`'s "Not staged" header.
- **Size:** tens of MB per year, so the dump costs nothing.

### Car backfill

Yes. Once the long-term instance lands:

- **Target:** point copyparty/03's import at `metrics-lt.SITE` only.
- **Backfill:** run `car_ingest.py` once with an empty or alternate state file. The
  sha256 state would otherwise skip every file.
- **Re-runs are safe:** `-dedup.minScrapeInterval=1ms` collapses duplicates with the same
  timestamp, and trips older than 10 years show up as
  `vm_rows_ignored_total{reason="small_timestamp"}`.
- **After the import:** call `/internal/resetRollupResultCache`. Auto-reset should cover
  it, but it's cheap.
- **In 03:** keep `result="too_old"` for samples past `long_term_years` instead of
  `metric_days`.

No separate backfill script is needed if 03 grows a `--reimport` flag.

### Not verified from a primary source

- Car data volume. The PIDs, sample rate and CSV layout wait on copyparty/02.
- Active series count and secsvcs free disk. Neither is in the repo; measure as above.
- Anchoring for `keep`/`keep_metrics` specifically. The docs state it only in the
  labeldrop/labelkeep section; it follows Prometheus semantics.
- Whether copying the live `-storageDataPath` without a snapshot is unsafe. The docs only
  forbid copying snapshot dirs.
- Whether alerting on long-term data needs a second vmalert. This is inferred from
  `-datasource.url` being a single value.

## Comments

- 2026-10-12: researched and resolved; see Answer.
