# 03. Extract car_ingest to car-ingest, run as a container

Status: resolved
Type: task
Repo: car-ingest (new), homelab
Source: maintainer request 2026-10-25

## Change

- New repo babraham123/car-ingest: `car_ingest.py`, stdlib only, the five Jinja values as flags
  and environment variables. The `.brc` and WiCAN JSONL notes from copyparty/03 and 05 move into
  its `docs/`. Containerfile, README, the tests ported.
- Homelab: run it on websvcs as a container built through the scan gate, replacing the host
  script, service and timer.

## Answer

Done 2026-10-25 (car-ingest `2fdf61d`; homelab branch `extract-car-ingest`).

- **Repo:** `--vm-url`, `--timezone`, `--retention-days`, `--default-car`, `--car-sources`, each
  also `CAR_INGEST_*` (timezone falls back to `TZ`); `--car-dir`, `--state-dir`,
  `--metrics-file`, `--vm-user`; the password only from `CAR_INGEST_VM_PASSWORD`.
  `car_ingest.py FILE` still prints a file's import lines. `docs/brc-format.md`,
  `docs/wican-jsonl.md`. Containerfile on `python:3.14-alpine` (tzdata and CA certificates
  included). 21 unittest cases.
- **Homelab:** `src/services/car_ingest/`: `build.sh` (`github_build`), a oneshot quadlet at
  websvcs `.26` with the `CAR_INGEST_*` values rendered from `vars.yml` and the
  `victoriametrics_admin_password` secret, mounting copyparty's `car/`, `/var/lib/car_ingest` and
  node_exporter's textfile directory; the timer, every 15 minutes. All capabilities dropped but
  `DAC_OVERRIDE`, which container root needs to move copyparty's files (1000:1000) and write the
  textfile directory. `inventory.yml` gains `car_ingest: {build: car_ingest}`. The host script,
  service and `tests/car_ingest_test.sh` are gone.
- The old install case called `install_timer`, removed on 2026-10-13, so the host version was
  probably never installed. 09 checks for a leftover unit.
