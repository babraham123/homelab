# Restore
How to get a file, a VM or a whole Proxmox host back from the weekly backup.

- What the backup holds: [Services: storage and backups](../services.md#storage-and-backups)
- What pve1 must keep off-box: [pve1 disaster recovery](./pve1_recovery.md)
- Everything in PBS is encrypted with `/root/secrets/pbs_client.key` on pve1; nothing restores
  without it. The escrow bundle that will hold it is *planned* (`backup-and-dr/04`)

Two tiers, cheapest first (the nodes keep no stage: `backup` streams it to pve1 and deletes it):
1. **pve1's collection**, `/root/backups/<node>/files/` on pve1
   - Every node's config trees and small volumes as of the last run, paths as on the live system,
     plus `repo/` (the repo and `vars.yml`, from every `tools/deploy_src.sh`)
   - A non-empty `dumps/` means the last upload failed and PBS doesn't have them
   - A fresh copy of one node: `/root/homelab-rendered/src/nodes/pve1/collect_stage.sh NODE`
2. **PBS** (`pbs2`, on pve2), every weekly run; needs pve2 awake: `ssh autoadmin@router start_pve2`
   - The only home of application dumps
   - Namespace `files`: `host/pve1`, the collection
   - Namespaces `pve1`, `pve2`: the VM images and `host/vpnsvcs`
   - Retention per namespace: [Storage and backups](../services.md#storage-and-backups)

## A file or an application's data
### From pve1's collection
```bash
# On pve1: paths as on the live system, for any node, as of the last Saturday run
ls /root/backups/secsvcs/files/etc/opt/
```
- `cp -a` the file back, then restart the service that reads it

### From PBS
For an application dump, anything older than the last run, or when pve1 is gone too:
```bash
# On pve1, or any machine with proxmox-backup-client, the token and the key
export PBS_REPOSITORY='pve1@pbs!backup@pbs2.janedoe.com:backup1'
export PBS_PASSWORD=$(sops -d /root/secrets/pve1.yaml | yq .pbs2_backup_token)
proxmox-backup-client snapshot list --ns files
proxmox-backup-client catalog dump host/pve1/2026-10-04T02:00:00Z backups.pxar --ns files \
  --keyfile /root/secrets/pbs_client.key | grep secsvcs/dumps
proxmox-backup-client restore host/pve1/2026-10-04T02:00:00Z backups.pxar /tmp/restore --ns files \
  --keyfile /root/secrets/pbs_client.key --pattern 'secsvcs/dumps/postgres/*'
# vpnsvcs is its own group, next to pve1's images
proxmox-backup-client snapshot list --ns pve1
proxmox-backup-client restore host/vpnsvcs/2026-10-04T02:00:00Z vpnsvcs.pxar /tmp/restore --ns pve1 \
  --keyfile /root/secrets/pbs_client.key --pattern 'dumps/headscale/*'
```
- `catalog shell` does the same interactively (`ls`, `select`, `restore-selected`)

### Application restores
Each dump restores into a fresh or stopped service; the file copies above cover the rest of
`/etc/opt`.

- **Postgres** (Authelia, LLDAP, Gatus, Grafana, Guacamole), from
  `secsvcs/dumps/postgres/pg_dumpall-*.sql.zst`:
```bash
# On secsvcs, with every other service stopped so nothing writes during the load
zstd -dc pg_dumpall-TIMESTAMP.sql.zst | podman exec -i postgres psql -U postgres
```
- **Home Assistant**, from `homesvcs/dumps/hass/hass-*.tar`
  - Settings >> System >> Backups >> upload, or copy it into the `hassconfig` volume's `backups/`
    and restore from there
  - Recorder history (`hassdb`) isn't backed up; HA creates an empty one
- **Headscale**, from `host/vpnsvcs`, `dumps/headscale/db-*.sqlite`:
```bash
systemctl stop headscale
cp db-TIMESTAMP.sqlite /var/lib/headscale/db.sqlite
rm -f /var/lib/headscale/db.sqlite-wal /var/lib/headscale/db.sqlite-shm
chown headscale:headscale /var/lib/headscale/db.sqlite
systemctl start headscale
```
- **A Podman volume copy** (`files/volumes/<name>/`, e.g. `grafanadata`, `z2mdb`): stop the service,
  `cp -a` the contents into
  `podman volume inspect -f '{{ .Mountpoint }}' systemd-<name>`, start it
- **The repo and `vars.yml`**, from `/root/backups/repo/homelab-*.tar.gz` on pve1: `tar -xzf` into
  an empty directory; `vars.yml` is in the archive root

## A VM
- From PBS, with pve2 awake
- Each backup carries the VM config (disks, NICs, MAC, passthrough): the VM keeps its DHCP lease and
  startup order
- **In place**, replacing a broken VM:
```bash
# On the host that owns the VM
pvesm list pbs2 | grep VMID      # newest first; check the dates
qm stop VMID
qmrestore pbs2:backup/vm/VMID/TIMESTAMP VMID --storage local-lvm --force
qm start VMID
```
- **To a scratch VMID**, to test or pick files out of a disk:
```bash
qmrestore pbs2:backup/vm/VMID/TIMESTAMP 999 --storage local-lvm --unique
qm set 999 --net0 virtio,bridge=vmbr0,link_down=1   # no network: same IP as the original
qm start 999
# Console in through the PVE UI, or mount its disk from the host:
# guestmount -a /dev/pve/vm-999-disk-0 -i --ro /mnt/scratch
qm destroy 999 --purge
```
- **UI**: the PBS storage >> Backups >> select >> Restore, or PBS's File Restore for single files
  (needs the key on the PVE storage: `pvesm set pbs2 --encryption-key`)
- **devtop and gaming on pve2**: data disks with `backup=0` aren't in the image; re-attach with
  `qm set VMID --scsi1 local-games:vm-VMID-disk-1,backup=0` (the `local-games` storage is *planned*,
  `backup-and-dr/14`)
- **The router**: the newest image is also on pve1's own disk, so it restores with pve2 off and
  the network down. pfSense's config is also in Auto Config Backup, but a VM restore is faster and
  keeps the NIC passthrough
```bash
# On pve1's console
ls /var/lib/vz/dump/    # vzdump-qemu-VMID-TIMESTAMP.vma.zst
qm stop VMID
qmrestore /var/lib/vz/dump/vzdump-qemu-VMID-TIMESTAMP.vma.zst VMID --storage local-lvm --force
```

## A Proxmox host
- **pve1**: [pve1 disaster recovery](./pve1_recovery.md)
- **pve2** (and PBS with it), with pve1 intact:
  1. Install Proxmox as in [the router guide](./router.md#install-proxmox), hostname `pve2`, static
     IP `192.168.2.10`; PBS as in [the Proxmox guide](./proxmox.md#backups); IOMMU and passthrough
     per [the GPU guide](./gpu.md) and [pve2 storage](./pve2_storage.md)
  2. **Datastore intact** (the SATA SSD survived):
     - Mount it where it was and recreate the datastore entry; PBS picks up the existing chunks and
       snapshots
     - Restore `/etc/proxmox-backup` from pve1's `/root/backups/pve2/files/etc/proxmox-backup/`
       (users, tokens, ACLs, jobs), then `systemctl restart proxmox-backup proxmox-backup-proxy`
  3. **Datastore lost**:
     - New `backup1` with namespaces `pve1`, `pve2` and `files`; recreate the `pve1@pbs!backup`
       token and ACLs ([Proxmox guide](./proxmox.md#backups)) and re-point pve1's `pbs2` storage
     - Everything only in PBS is gone until the offsite copy exists (`backup-and-dr/03`); rebuild
       pve2's VMs from their guides and pve1's `/root/backups/websvcs`
  4. Restore `/etc/pve/storage.cfg` and `priv/storage/pbs2.*` from
     `/root/backups/pve2/files/etc/pve/` (the `pbs2` storage and its key), then `qmrestore` websvcs,
     devtop and gaming as above
  5. `tools/deploy_src.sh`; `install_dispatcher`, `install_vm_watchdog`, `install_certs_and_keys` on
     pve2; `install_all_svcs` on websvcs

## Annual restore test
Record the date in `docs/maintenance.md` when done.
1. Wake pve2 and restore secsvcs to VMID 999 with `--unique` and the NIC down, as above
   - Boot it and log in on the console
   - `systemctl list-units 'Homelab*'` shows every service running
   - `podman exec postgres psql -U postgres -c '\l'` lists the databases
   - Destroy it
2. Pull one file out of the newest host backup with `proxmox-backup-client restore ... --pattern`,
   e.g. the Headscale DB, and check it: `sqlite3 db-*.sqlite 'PRAGMA integrity_check'`
3. Once the escrow bundle exists (*planned*, `backup-and-dr/04`): decrypt a copy of the client key
   from it, not pve1, to prove the escrow is current
