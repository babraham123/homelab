# 02. Fork and vendor the Traefik rewrite-headers plugin as a local plugin

Status: ready-for-human
Type: task
Repo: homelab
Source: review finding 10

## Problem

`src/services/traefik/static.yml.j2` loads `github.com/bitrvmpd/traefik-plugin-rewrite-headers`
v0.0.1 from GitHub at startup via Yaegi: a single-maintainer, unpinned-by-digest dependency inside
the TLS terminator, plus a hard startup dependency on GitHub.

## Change

1. Fork the upstream `https://github.com/bitrvmpd/traefik-plugin-rewrite-headers` into your GitHub
   account (human step: create the fork). Review the source; it is small. Then port the one feature
   from the `connectionloops` fork (a fork of the same upstream, 0 stars): rewriting the `Host`
   header also sets `req.Host`, which Go's `http.Request` keeps separately. Its patch to
   `rewrite_headers.go` is:

   ```go
   // Special case for "Host"
   if strings.EqualFold(rewrite.header, "Host") {
       req.Host = strings.TrimSpace(value)
   }
   ```

   Take that block only; drop its `os.Stdout.WriteString` debug line and leave `.traefik.yml`
   `import:` pointing at your fork. Add a test case for `Host` next to the existing ones.
2. Vendor the source into this repo at
   `src/services/traefik/plugins-local/src/github.com/<you>/traefik-plugin-rewrite-headers/`
   (Traefik's local-plugin layout requires this exact path shape and a `.traefik.yml` manifest at
   the plugin root).
3. In `static.yml.j2` replace `experimental.plugins.rewriteHeaders` with
   `experimental.localPlugins.rewriteHeaders.moduleName: github.com/<you>/traefik-plugin-rewrite-headers`.
4. Mount it in every Traefik quadlet
   (`src/nodes/{secsvcs,homesvcs,websvcs}/traefik/traefik.container.j2`):
   `Volume=/etc/opt/traefik/plugins-local:/plugins-local:ro`, and copy the directory in each node's
   `install_svcs.sh traefik` case.
5. Middleware reference in `src/nodes/secsvcs/traefik/basic_auth.yml` stays `vm-auth-token`; the
   plugin key name is unchanged.

## Acceptance

- Traefik starts with GitHub blocked (test with `AddHost=github.com:127.0.0.1` or by observing no
  outbound fetch in logs).
- The `Authorization: Token ...` → `Basic ...` rewrite still works for the HA → VictoriaMetrics
  path.

## Comments

- 2026-10-10: Steps 1-5 done in the repo. The source is v0.0.1 (e2421fa) of the upstream, vendored
  at `src/services/traefik/plugins-local/src/github.com/babraham123/traefik-plugin-rewrite-headers/`
  with `go.mod`, `.traefik.yml` and the readme pointing at `babraham123`, the `Host` block ported
  without the debug line, and two tests added: `Host` (header and `req.Host`) and the `Token` →
  `Basic` rewrite used by `vm-auth-token`. `go test` and `yaegi test` pass. Each node's
  `install_svcs.sh traefik` replaces `/etc/opt/traefik/plugins-local`; the quadlets mount it
  read-only. Remaining for the human: create the GitHub fork (nothing fetches it; it only records
  where the vendored copy comes from), then on each node run `install_traefik` and check the
  acceptance items.
- 2026-10-10: Fork created; the vendored source is pushed to it as 92d799d on `main`. Remaining: run
  `install_traefik` on each node and check the acceptance items.
