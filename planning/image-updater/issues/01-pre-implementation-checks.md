# 01. Run the six pre-implementation checks

Status: ready-for-human
Type: research
Repo: homelab
Source: notes/image-updater-design.md "Checks before implementation"

## Task

Quick tests on one VM each. None blocks the design, but 3 and 6 decide the timer
settings in 06, and 4 decides the rollback logic in 03.

1. **Multi-arch digests.** Does `skopeo inspect` on a multi-arch tag return the same
   digest as the local copy? (Shows whether remote-vs-remote state comparison was
   required or just careful.)
2. **`.trivyignore` expiry.** Scan with an `exp:` date in the past; the CVE must be
   reported again.
3. **Boot deadlock.** On homesvcs, a `Type=exec` unit that waits with
   `systemctl is-system-running --wait`, `Persistent=true`, reboot across a missed slot.
   Boot finishes and the run starts.
4. **Rollback behavior.** Force a failing `AutoUpdate=local` update on a test
   container. Record the `Updated` value in `podman auto-update --format json` and where
   the tag points afterwards.
5. **Gatus heartbeat.** Confirm external-endpoint heartbeats work in the deployed
   `gatus:latest`.
6. **Run duration.** Time `skopeo inspect` + `skopeo copy` + `trivy image --input` over
   every image on each VM; the schedule assumes each run fits in 30 minutes.

Record results under `## Answer`, and fold any change into `notes/image-updater-design.md`.

## Comments
