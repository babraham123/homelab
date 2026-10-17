# 02. Capture a sample Car Scanner Pro export

Status: resolved
Type: task
Repo: homelab
Source: maintainer request 2026-09-26

## Task

1. Record a short drive in Car Scanner Pro, including GPS if the app can log it.
2. Export the log as CSV using the same export path you will use day to day, so the format matches
   what 03 will parse.
3. Save it as `planning/copyparty/sample-car-scanner.csv`. Trim it to a few hundred rows, and strip
   or round GPS coordinates near home if that matters to you.
4. Under `## Answer`, record:
   - app version;
   - export settings (units, separator, which PIDs were logged);
   - whether the timestamp column is absolute or seconds since trip start;
   - the filename pattern the app uses (03 derives the `trip` label and, if needed, the start time
     from it).

## Answer

Captured 2026-05-24 as `notes/2026-05-24 20-10-53.{csv,brc}`, both exported via Share: a 160 s
session on a Kia EV6 with a vLinker MC adapter. The files stay in the gitignored `notes/`, not under
`planning/`, because the BRC header carries the VIN and the adapter's MAC address and this repo is
public.

- App version: not recorded. Neither file contains it; the BRC format version is `2`.
- Export settings: imperial display units (°F, miles), `;` separator, every field quoted, a
  trailing `;` on each line, mixed CRLF/LF line endings. 280 sensors were logged: OBD standard PIDs
  plus the `[BMS]` set (192 cell voltages, pack temperatures, SoC/SoH, power, cumulative energy).
  No GPS.
- Timestamps: CSV `SECONDS` is seconds since local midnight of the start day (`72729.4` =
  20:12:09), with no date. BRC stores the absolute start time plus seconds since start.
- Filename: `YYYY-MM-DD HH-MM-SS` of recording start, local time.

04 found that the `.brc` the app saves on its own is the better input. 03 parses BRC; the format is
documented there.

## Comments
