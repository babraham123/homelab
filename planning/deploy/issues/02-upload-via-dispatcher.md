# 02. Upload rendered tree through the autoadmin dispatcher

Status: wontfix
Type: task
Repo: homelab
Source: review finding 46

Maintainer decision: rejected — letting `autoadmin` write the rendered tree that
`autoadmin`'s own whitelisted commands then execute would collapse the privilege
boundary. Uploads stay interactive via `manualadmin`.

## Comments
