# Restore

Get a file, a VM or a whole Proxmox host back from the weekly backup.

- Backup contents: [Services: storage and backups](../services.md#storage-and-backups)
- pve1's off-box keys: [pve1 disaster recovery](./pve1_recovery.md)
- Nothing in PBS restores without `/root/secrets/pbs_client.key` from pve1
- Sources, cheapest first:
  1. pve1's collection, `/root/backups/<node>/files/`: every node's configs and small volumes as of
     the last run, plus `repo/`
     - A non-empty `dumps/` means the last PBS upload failed
     - Refresh one node: `/root/homelab-rendered/src/nodes/pve1/collect_stage.sh NODE`
  2. PBS (`pbs2` on pve2): every weekly run, and the only copy of application dumps
     - Wake pve2: `ssh autoadmin@router start_pve2`
     - Namespace `files`: `host/pve1`; namespaces `pve1`, `pve2`: VM images and `host/vpnsvcs`

## A file or an application's data

### From pve1's collection

```bash
ls /root/backups/secsvcs/files/etc/opt/
```

- `cp -a` the file back, then restart the service that reads it

### From PBS

```bash
# On pve1, or any machine with proxmox-backup-client, the token and the key
export PBS_REPOSITORY='pve1@pbs!backup@pbs2.janedoe.com:backup1'
export PBS_PASSWORD=$(sops -d /root/secrets/pve1.yaml | yq .pbs2_backup_token)
proxmox-backup-client snapshot list --ns files
proxmox-backup-client catalog dump host/pve1/2026-10-04T02:00:00Z backups.pxar --ns files \
  --keyfile /root/secrets/pbs_client.key | grep secsvcs/dumps
proxmox-backup-client restore host/pve1/2026-10-04T02:00:00Z backups.pxar /tmp/restore --ns files \
  --keyfile /root/secrets/pbs_client.key --pattern 'secsvcs/dumps/postgres/*'
# vpnsvcs
proxmox-backup-client snapshot list --ns pve1
proxmox-backup-client restore host/vpnsvcs/2026-10-04T02:00:00Z vpnsvcs.pxar /tmp/restore --ns pve1 \
  --keyfile /root/secrets/pbs_client.key --pattern 'dumps/headscale/*'
```

- Interactive: `catalog shell` (`ls`, `select`, `restore-selected`)

### Application restores

- **Postgres**, from `secsvcs/dumps/postgres/pg_dumpall-*.sql.zst`

```bash
# On secsvcs, with every other service stopped
zstd -dc pg_dumpall-TIMESTAMP.sql.zst | podman exec -i postgres psql -U postgres
```

- **Home Assistant**, from `homesvcs/dumps/hass/hass-*.tar`
  - Settings >> System >> Backups >> upload, or copy it into the `hassconfig` volume's `backups/`
  - Recorder history (`hassdb`) isn't backed up
- **Headscale**, from `host/vpnsvcs`, `dumps/headscale/db-*.sqlite`

```bash
systemctl stop headscale
cp db-TIMESTAMP.sqlite /var/lib/headscale/db.sqlite
rm -f /var/lib/headscale/db.sqlite-wal /var/lib/headscale/db.sqlite-shm
chown headscale:headscale /var/lib/headscale/db.sqlite
systemctl start headscale
```

- **A Podman volume** (`files/volumes/<name>/`): stop the service, `cp -a` into
  `podman volume inspect -f '{{ .Mountpoint }}' systemd-<name>`, start it
- **Repo and `vars.yml`**: `tar -xzf /root/backups/repo/homelab-*.tar.gz` on pve1 into an empty dir

## A VM

- From PBS, with pve2 awake. The image includes the VM config (NICs, MAC, passthrough)
- In place

```bash
# On the host that owns the VM
pvesm list pbs2 | grep VMID
qm stop VMID
qmrestore pbs2:backup/vm/VMID/TIMESTAMP VMID --storage local-lvm --force
qm start VMID
```

- To a scratch VMID

```bash
qmrestore pbs2:backup/vm/VMID/TIMESTAMP 999 --storage local-lvm --unique
qm set 999 --net0 virtio,bridge=vmbr0,link_down=1   # same IP as the original
qm start 999
# guestmount -a /dev/pve/vm-999-disk-0 -i --ro /mnt/scratch
qm destroy 999 --purge
```

- UI: PBS storage >> Backups >> Restore, or File Restore (`pvesm set pbs2 --encryption-key`)
- devtop and gaming: re-attach `backup=0` data disks with
  `qm set VMID --scsi1 local-games:vm-VMID-disk-1,backup=0`
- The router: restore from pve1's disk, works with pve2 off

```bash
# On pve1's console
ls /var/lib/vz/dump/
qm stop VMID
qmrestore /var/lib/vz/dump/vzdump-qemu-VMID-TIMESTAMP.vma.zst VMID --storage local-lvm --force
```

## A Proxmox host

- pve1: [pve1 disaster recovery](./pve1_recovery.md)
- pve2, with pve1 intact:
  1. Install Proxmox as in [the router guide](./router.md#install-proxmox), hostname `pve2`, IP
     `192.168.2.10`; PBS per [the Proxmox guide](./proxmox.md#backups); passthrough per
     [GPU](./gpu.md) and [pve2 storage](./pve2_storage.md)
  2. Datastore intact:
     - Mount the SATA SSD where it was and recreate the datastore entry
     - Copy back `/etc/proxmox-backup` from pve1's `/root/backups/pve2/files/etc/proxmox-backup/`,
       then `systemctl restart proxmox-backup proxmox-backup-proxy`
  3. Datastore lost:
     - New `backup1` with namespaces `pve1`, `pve2`, `files`; recreate the `pve1@pbs!backup` token
       and ACLs ([Proxmox guide](./proxmox.md#backups)); re-point pve1's `pbs2` storage
     - Rebuild pve2's VMs from their guides and pve1's `/root/backups/websvcs`
  4. Copy back `/etc/pve/storage.cfg` and `priv/storage/pbs2.*` from
     `/root/backups/pve2/files/etc/pve/`, then `qmrestore` websvcs, devtop and gaming
  5. `tools/deploy_src.sh`; `install_dispatcher`, `install_vm_watchdog`, `install_certs_and_keys` on
     pve2; `install_all_svcs` on websvcs

## Annual restore test

Record the date in `docs/maintenance.md`.

1. Wake pve2, restore secsvcs to VMID 999 with `--unique` and the NIC down
   - Log in on the console
   - `systemctl list-units 'Homelab*'`: every service running
   - `podman exec postgres psql -U postgres -c '\l'`: lists the databases
   - Destroy it
2. Restore the newest Headscale DB with `proxmox-backup-client restore ... --pattern`, then
   `sqlite3 db-*.sqlite 'PRAGMA integrity_check'`
