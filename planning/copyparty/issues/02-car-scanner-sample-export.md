# 02. Capture a sample Car Scanner Pro export

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-09-26

## Task

1. Record a short drive in Car Scanner Pro, including GPS if the app can log it.
2. Export the log as CSV using the same export path you will use day to day, so the
   format matches what 03 will parse.
3. Save it as `planning/copyparty/sample-car-scanner.csv`. Trim it to a few hundred
   rows, and strip or round GPS coordinates near home if that matters to you.
4. Under `## Answer`, record:
   - app version;
   - export settings (units, separator, which PIDs were logged);
   - whether the timestamp column is absolute or seconds since trip start;
   - the filename pattern the app uses (03 derives the `trip` label and, if needed, the
     start time from it).

## Comments
