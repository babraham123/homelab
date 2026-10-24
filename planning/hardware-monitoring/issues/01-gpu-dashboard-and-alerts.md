# 01. GPU dashboard and temperature alerts

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-23

## Problem

Three exporters report the Tesla P4 (websvcs) and the RTX 3060 Ti (devtop or gaming), and
nothing reads them. The P4 has no fan of its own and lives on case airflow, so a hot card goes
unnoticed until a job slows down.

## Change

1. **Alerts**, in a new `src/services/vmalert/configs/hardware.yml`, group `gpus`. Every series
   carries only `uuid`, so join `nvidia_smi_gpu_info` on `(host, uuid)` for the card's name:
   - `GpuHot`: `nvidia_smi_temperature_gpu > 85` for 5m, warning; the same threshold as
     `HighCpuTemp`.
   - `GpuThermalThrottling`: any
     `nvidia_smi_clocks_(event|throttle)_reasons_(hw|sw)_thermal_slowdown == 1` for 5m, warning.
     Drivers from 535 name the flags `clocks_event_reasons`, older ones `clocks_throttle_reasons`,
     and the exporter auto-discovers whichever the driver has.
   - `GpuRecoveryNeeded`: `nvidia_smi_gpu_recovery_action > 0`, error. Only recent drivers report
     it; absent is fine.
2. **Dashboard** `src/services/grafana/dashboards/gpu.json`, hand-written like `car.json`, `host`
   and `gpu` variables, both GPU jobs:
   - Stats: temperature, power draw against the enforced limit, utilisation, memory used
   - Time series: temperature, power, energy per day (`integrate()` of power draw), GPU and
     memory utilisation, fan (the P4 reports none), graphics and memory clocks, throttle flags
3. **Docs**: `docs/services.md` alert list and the nvidia_gpu_exporter row.

## Acceptance

- `vmalert` loads `hardware.yml` (`/api/v1/rules` lists the `gpus` group).
- The dashboard shows the P4 with websvcs up, and the 3060 Ti with devtop or gaming up.
- A load test on the P4 (Calliope job) shows on the power and temperature panels.

## Comments

- 2026-10-23: code in. `hardware.yml` group `gpus` (`GpuHot`, `GpuThermalThrottling`,
  `GpuRecoveryNeeded`) and `gpu.json` ("GPUs"). Not yet checked against a live exporter:
  confirm `nvidia_smi_clocks_current_*_clock_hz`, `nvidia_smi_utilization_memory_ratio` and the
  slowdown flag names on the P4's driver, and `vmalert -dryRun` the rules at deploy.
