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
Refer to [claude.md](../CLAUDE.md)
