# autoadmin file access

The dispatchers pass sftp through for the autoadmin key, which gives any autoadmin key (OliveTin's
included) read and write access to autoadmin's files, the backup stage and the inputs of root
install commands. Close it without breaking backups and cert distribution.

## Issues

| # | Title | Status | Type |
|---|---|---|---|
| [01](issues/01-sftp-passthrough.md) | The dispatcher's sftp passthrough gives autoadmin keys file access | `resolved` | research |
