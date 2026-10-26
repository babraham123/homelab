# GitHub repository rules

The homelab and the repos it builds or installs from share one set of GitHub settings. A merge to
`main` in a container repo reaches every node the next night (the image updater builds `main`),
and the homelab pins commits of the others, so `main` is treated as the deploy branch.

## Settings

| Setting | Why |
| --- | --- |
| Ruleset on the default branch: no deletion, no force push | A rewritten commit is eventually garbage-collected, and installs pinned to it fail |
| Ruleset: a pull request with one approval, dismissed by new pushes and given after the last one | Renovate PRs reach the nodes only after a review |
| Ruleset: required CI checks, reported by GitHub Actions only (`integration_id` 15368), branch need not be up to date | A failing PR can't merge, and no other app or token can fake a pass |
| Ruleset bypass: repository admins | You push straight to `main` and merge your own PRs, which GitHub won't let you approve |
| Actions: full commit SHA pins required | A tag can be moved to other code; Renovate keeps the pins current |
| Actions: read-only default token; workflows can't create or approve PRs | A workflow gets write access only by asking for it |
| Secret scanning with push protection | A push containing a known token format is rejected |
| Dependabot alerts on; Dependabot security PRs and version updates off | Renovate opens the fix PRs (from the alerts and from OSV), so they follow its grouping and holds |

The rules live only in rulesets; no repo has a classic branch protection. The homelab and homesite
also require review threads to be resolved before a merge.

## Required checks

| Repo | Checks |
| --- | --- |
| homelab | `check` |
| podman-image-updater, net-probe, TTS-Narrated-Ebook-Creator | `test` |
| car-ingest, bookmark-handoff, yt-to-audiobook, ntfy-idp-push, finance-exporter | `test`, `image` |
| homesite | `site` |
| haproxy-mapper | `build`, `geoip_generator_image` |
| bt-courier-android | `test`, `reproducible-build (ubuntu-22.04)`, `reproducible-build (ubuntu-24.04)`, `reproducible-compare`, `secret-scan` |

A required check that is skipped counts as passed, so a job that only runs after others (like
`reproducible-compare`) is listed together with the jobs it waits on. Renaming a CI job means
updating the ruleset, or every PR waits on a check that never reports.

## Renovate

Every repo has a `renovate.json` that runs on Monday mornings, waits 3 days after a release (for
Maven artifacts in bt-courier-android, only when the registry says when it was released; never for
a PR that only pins the version in use), and pins Actions by digest. Repos with a Containerfile or
Dockerfile pin its base images by digest too, and all but the homelab turn on
`osvVulnerabilityAlerts`, which opens fix PRs outside the schedule.
TTS-Narrated-Ebook-Creator holds the CUDA base at 12.4 and skips torch, torchaudio and
CTranslate2, whose newer builds drop CUDA 12.4 or Pascal.

In the homelab, Renovate updates only the images pinned to a version (`upstream:` in the node
inventories, the quadlets' `Image=localhost/...` and any other mention under `src/`, `docs/` and
`rendered/`), plus the tool versions in CI and the pre-commit hook. Floating tags are the image
updater's job, and pinning their digests would bypass its scan. A new major version waits for
approval on the Dependency Dashboard, since it usually needs a migration.

## Checking a repo

```bash
gh api repos/babraham123/REPO/rulesets                 # then rulesets/ID for the rules
gh api repos/babraham123/REPO/actions/permissions
gh api repos/babraham123/REPO/actions/permissions/workflow
gh api repos/babraham123/REPO -q .security_and_analysis
gh api repos/babraham123/REPO/vulnerability-alerts     # 204: alerts on, 404: off
```
