# Development
TODO: fill in

[MAC setup](./guides/mac.md)

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
- Update traefik config for that VM
- Internal only route, update unbound config
- service container and configs
- install script
- local cert and key if cross VM communication
  - if it's the server, update cert and key gen scripts
  - otherwise the CA cert should be sufficient
- update guide for that VM
- Authelia config
- Gatus config
- homepage config and icon
