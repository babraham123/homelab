# Development
TODO: fill in

[MAC setup](./guides/mac_personal.md)

## Deploy new configurations

- Create a `vars.yml` file from `vars.template.yml`
- Render the files and upload to a server
```bash
tools/render_src.sh /tmp/homelab-rendered
tools/upload_src.sh secsvcs /tmp/homelab-rendered
```
- Render and upload to all servers
```bash
tools/deploy_src.sh
```

## Add a new service
1. Add Traefik route config for the VM
1. Create service container and config files in `src/<service>/`
1. If cross-VM TLS is needed, add cert/key gen to `src/certificates/` and update `install_files.sh`
1. Add service to `install_svcs.sh`
1. Update Authelia config if OIDC auth is available (`src/authelia/`)
1. Add Gatus uptime check (`src/gatus/config.yaml`)
1. Add Homepage dashboard entry (`src/homepage/`)
1. Update the relevant guide in `docs/guides/`
