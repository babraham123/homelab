# pve1 disaster recovery
What pve1 must keep off-box, and how to recover when its SSD dies or a trust root (AGE key, private
CA, SSH CA, `vars.yml`) is lost.

- pve1 is the one host a VM restore can't bring back: the private CA, SSH CA, AGE key, ACME
  distribution and secret provisioning live on the Proxmox host, outside every VM backup
- The weekly run ([Services](../services.md#storage-and-backups)) sends pve1's host files
  (`/root/secrets`, `/root/ca`, `/root/ssh`, `/etc/pve`, …) to PBS as `host/pve1`, and its VMs as
  images, all encrypted with `/root/secrets/pbs_client.key`
- The escrow bundle (*planned*, `backup-and-dr/04`) must hold that key and the PBS token. Until
  then, see [Nothing escrowed](#nothing-escrowed)
- `backup-and-dr/NN` tickets are in `planning/backup-and-dr/issues/`; anything *planned* doesn't
  exist yet

## What must exist off-box
The canonical list: `backup-and-dr/04` escrows it, the weekly run backs it up. "Covered by":
- **PBS VM backup**: inside a VM disk that PBS backs up
- **PBS host backup**: staged by pve1's `backup.sh` into `/root/backups/pve1/` and uploaded with the
  rest of `/root/backups`; needs the client key and a token to restore
- **Escrow**: the escrow bundle, *planned* (`backup-and-dr/04`)
- **Repo backup**: `/root/backups/repo/`, written by every `tools/deploy_src.sh`, in the PBS host
  backup
- **Regenerate**: derived; rebuild with the script or guide listed

### On pve1

| Path on pve1 | What | Covered by | If lost |
|---|---|---|---|
| `/root/secrets/age.txt`, `age.pub` | AGE identity; every SOPS file and every host's `secrets.yaml.age` is encrypted to it | Escrow, PBS host backup | [Only the AGE key is lost](#only-the-age-key-is-lost) |
| `/root/secrets/pbs_client.key` | PBS client encryption key; everything in PBS is ciphertext under it | Escrow; pve2's `pbs2` storage holds the same key (`/etc/pve/priv/storage/pbs2.enc`). The copy in PBS is encrypted with itself | Nothing in PBS restores. Rebuild everything from the guides |
| `/root/secrets/pve1.yaml` | pve1's secrets: `msmtp_password`, `pbs2_api_password`, `pbs2_backup_token`, MaxMind keys | Escrow, PBS host backup | Re-enter from `src/nodes/pve1/secrets_template.yaml`; a new PBS token per the [Proxmox guide](./proxmox.md#backups) |
| `/root/secrets/{secsvcs,homesvcs,websvcs,vpnsvcs}.yaml` | SOPS source of each host's secrets | Escrow, PBS host backup | Rebuild from the host's own copy ([AGE scenario](#only-the-age-key-is-lost)) |
| `/root/secrets/<host>.yaml.age` | per-host `age` copy pushed to `/etc/opt/secrets/secrets.yaml.age` | Regenerate | `secret_update.sh <host>` |
| `/root/secrets/<host>_id_ed25519.pub` | host recipient key | Regenerate | re-`scp` from the host ([pve1 guide](./pve1.md#secrets)) |
| `/root/ca/private/ca.key.pem`, `certs/ca.cert.pem`, `index.txt`, `serial`, `crlnumber` | root CA | Escrow, PBS host backup | [Only the private CA is lost](#only-the-private-ca-is-lost) |
| `/root/ca/intermediate/private/intermediate.key.pem`, `certs/intermediate.cert.pem`, `certs/ca-chain.cert.pem`, `index.txt`, `serial`, `crlnumber`, `crl/` | intermediate CA | Escrow, PBS host backup | same |
| `/root/ca/intermediate/private/*.janedoe.com.key.pem`, `certs/`, `csr/` | per-service keys, certs and CSRs | Escrow (part of `/root/ca`), PBS host backup | `self_signed_key_gen.sh` + `self_signed_cert_gen.sh` |
| `/root/ca/openssl.cnf`, `/root/ca/intermediate/openssl.cnf` | CA config | Regenerate | rendered `src/nodes/pve1/certificates/openssl.{root,intermediate}.cnf` |
| `/root/ssh/ca_ssh_key`, `ca_ssh_key.pub` | SSH user CA: signs client keys for `manualadmin`/`autoadmin` | Escrow, PBS host backup | [Only the SSH CA is lost](#only-the-ssh-ca-is-lost) |
| `/root/ssh/ca_ssh_host_key`, `ca_ssh_host_key.pub` | SSH host CA: behind every `@cert-authority` line | Escrow, PBS host backup | same |
| `/root/ssh/known_hosts`, `public/`, `date_ssh_certs*.txt` | host pubkeys and certs, `@cert-authority` line, renewal timestamps | Regenerate | `ssh_cert_gen.sh`, `ssh_cert_gen_windows.sh` |
| Passphrases of `ca.key.pem`, `intermediate.key.pem`, `ca_ssh_key` | not files; asked for at signing time | Offline copy held by the maintainer; a better home is `auth/08` | the escrowed keys are useless without them |
| `/root/acme/` | copies of each Traefik's `acme.json`, dumped certs, `pbs2_cert_info.txt`, `date_acme_certs.txt` | Regenerate | `acme_transfer.sh` |
| `/root/.ssh/id_ed25519`, `id_ed25519-cert.pub` | root's client key, signed as `manualadmin,autoadmin`; every pve1 script SSHes with it | Regenerate | new key + re-sign ([step 10](#10-ssh-root-key-and-host-certs)) |
| `/etc/pve/storage.cfg`, `/etc/pve/priv/storage/pbs2.*` | `pbs2` storage entry, its token and the encryption key | PBS host backup | re-add the storage ([step 3](#3-reconnect-the-pbs-storage)) |
| `/etc/pve/user.cfg`, `qemu-server/*.conf` | `api_ro` user, VM configs | PBS host backup; VM configs also in each PBS VM backup | VM configs return with `qmrestore`; recreate users ([Proxmox guide](./proxmox.md#backups)) |
| `/etc/network/interfaces`, `/etc/resolv.conf` | host network | Regenerate | from `src/nodes/pve1/interfaces.j2`, `src/nodes/pve1/resolv.conf.j2` |
| `/root/homelab-rendered/` | rendered repo | Regenerate | `tools/deploy_src.sh` from the workstation |
| `/etc/msmtprc`, `/usr/local/bin/{cert_notifier,vm_watchdog,backup_orchestrator}.sh`, their systemd units, the msmtp AppArmor edit, node_exporter | host services | Regenerate | [step 11](#11-host-services) |
| `/root/backups/` | every node's staged files and dumps as of the last run, and `repo/` | PBS host backup | nothing: the nodes keep no stage |

### Elsewhere

| Where | What | Covered by | If lost |
|---|---|---|---|
| `vars.yml` on the workstation | every personal value the render needs | Repo backup (every deploy), Escrow | [Only vars.yml is lost](#only-varsyml-is-lost) |
| `/etc/opt/traefik/certificates/acme.json` on secsvcs, homesvcs, websvcs | Let's Encrypt account key + certs | PBS VM backup | Traefik re-issues on start (rate limits apply) |
| `/etc/opt/olive_tin/ssh/` on secsvcs | OliveTin's `autoadmin` key + cert | PBS VM backup | `ssh_cert_gen.sh` |
| `/etc/opt/secrets/id_ed25519`, `secrets.yaml.age` on each host | host decryption key + that host's secrets | PBS VM backup; vpnsvcs: PBS `host/vpnsvcs` | new key, re-collect pubkey, `secret_update.sh <host>` |
| pfSense `config.xml` | firewall, VLANs, DHCP leases, DNS | PBS VM backup (router VM), Auto Config Backup; *planned*: Escrow | [Router without a VM backup](#router-without-a-vm-backup) |
| ACB device key + encryption password | needed to pull an ACB backup onto a fresh pfSense | Offline copy held by the maintainer; see `auth/08` | ACB backups unusable |
| PBS datastore `backup1` on pve2 | every VM and host backup | nothing (single copy); *planned*: offsite (`backup-and-dr/03`) | rebuild VMs from the guides; pve1's `/root/backups` holds the last files |

## Rebuild pve1 from bare metal
- Assumes a new SSD, pve2 and its datastore intact, and `vars.yml`
- All four NICs belong to the router VM: no LAN, DHCP, DNS or Wake-on-LAN until it's back. Work from
  pve1's console until step 5
- More on VM restores: [restore guide](./restore.md#a-vm)

### 1. Install Proxmox with a temporary link to pve2
- Install Proxmox as in the [router guide](./router.md#install-proxmox); the user and desktop steps
  can wait
- Hostname `pve1.janedoe.com`. The node name must be `pve1`: restored VM configs land under
  `/etc/pve/nodes/pve1/`, and the scripts look the host up by name. Renaming after step 4 orphans
  the restored VMs
- Network: the NIC cabled to pve2 (pfSense's `igc2`), a free static address on pve2's subnet, e.g.
  `192.168.2.250/24`, gateway `192.168.2.1`
  - Ports are in PCI order: WAN, LAN (WiFi AP), pve2, LAN2 (switch). pve2's is the third controller
    in `lspci -nn | grep -i ethernet`
  - PCI address `BB:00.0` → `enp<N>s0`, `N` = `BB` in decimal (`03` → `enp3s0`, `0a` → `enp10s0`)
  - `ip -br link`: only the cabled ports are `UP`
- Enable IOMMU and the vfio modules now ([router guide](./router.md#install-pfsense), "Enable IOMMU
  / NIC passthrough"); the router VM can't start without them

### 2. Power on pve2 by hand
- Press pve2's power button (`start_pve2` needs the router)
- pve2 comes up on its static `192.168.2.10`, PBS on `:8007`

### 3. Reconnect the PBS storage
- Needs the client key and a PBS token:
  - Key: `pbs_client.key` from escrow, or pve2's copy, `/etc/pve/priv/storage/pbs2.enc`; put it at
    `/root/secrets/pbs_client.key` (`install -D -m 400`)
  - Token: `pbs2_backup_token` from escrow (in `pve1.yaml`), or a new one made on pve2 ([Proxmox
    guide](./proxmox.md#backups))
- The fingerprint is needed until step 12 installs the Let's Encrypt cert
```bash
# On pve2's console
proxmox-backup-manager cert info | grep Fingerprint

# On pve1
pvesm add pbs pbs2 --server 192.168.2.10 --datastore backup1 --namespace pve1 \
  --username 'pve1@pbs!backup' --password 'TOKEN_SECRET' --fingerprint 'FINGERPRINT' \
  --encryption-key /root/secrets/pbs_client.key
pvesm list pbs2
```

### 4. Restore the VMs
- Restore the router, secsvcs and homesvcs while the temporary link is up; don't start them
```bash
pvesm list pbs2    # newest backup per VMID; check the dates
qmrestore pbs2:backup/vm/VMID/TIMESTAMP VMID --storage local-lvm
```
- Each backup carries its VM config: NIC passthrough (`hostpci0`–`hostpci3`), MACs, startup order
- Router backup missing or broken: [Router without a VM backup](#router-without-a-vm-backup)

### 5. Switch pve1 to its normal network and start the router
- `vmbr0` has no bridge ports; pfSense is the gateway
- The rendered tree isn't on pve1 yet: write `/etc/network/interfaces` and `/etc/resolv.conf` by
  hand from `src/nodes/pve1/interfaces.j2` and `src/nodes/pve1/resolv.conf.j2`
  - `vmbr0` static `192.168.4.10/24`, gateway `192.168.4.1`, `bridge-ports none`
  - `search janedoe.com`, `nameserver 192.168.4.1`
```bash
ifreload -a
qm start ROUTER_VMID
ping 192.168.2.10
```
- From a LAN client, open `https://192.168.1.1/`

### 6. Start the remaining VMs
```bash
# pve1
qm start SECSVCS_VMID
qm start HOMESVCS_VMID
# pve2, if they aren't set to start at boot; step 10 needs them
qm start WEBSVCS_VMID
qm start DEVTOP_VMID
```
- Same MACs, so pfSense's static leases hand back the same IPs
- Their state is whatever the backup held; they don't need the pve1 host to run
- Smoke test: log in at `https://auth.janedoe.com`

### 7. Base host setup
- Proxmox repos and the `manualadmin` user: [router guide](./router.md#install-proxmox)
- [Debian setup](./debian.md) up to, not including, "Homelab Repo"

### 8. Re-render and upload
```bash
# From the workstation, repo root. Drop the old host keys or ssh refuses the new one
ssh-keygen -R pve1; ssh-keygen -R pve1.janedoe.com; ssh-keygen -R 192.168.4.10
tools/deploy_src.sh
```
- Expect a first-connection prompt: the new host key isn't CA-signed until step 10
- `deploy_src.sh` doesn't stop on a failed host; check for `pve1 upload failed`
- Then on pve1:
  - [Debian setup, Automation](./debian.md#automation): `autoadmin` user and `install_dispatcher`
  - [pve1 guide, Configs](./pve1.md#configs): jinjanator, yq
  - [pve1 guide, Secrets](./pve1.md#secrets): the first block only (age, sops, the shell exports);
    skip `age-keygen`

### 9. Restore the trust roots
- From PBS: install the client and pull `/root` out of the newest host backup ([restore
  guide](./restore.md#from-pbs))
```bash
/root/homelab-rendered/src/nodes/pve1/install_svcs.sh backup_orchestrator
proxmox-backup-client restore host/pve1/TIMESTAMP backups.pxar /tmp/restore --ns files \
  --keyfile /root/secrets/pbs_client.key --pattern 'pve1/*'
```
  Then copy `pve1/files/root/{secrets,ca,ssh,acme,.ssh}` into place.
- Or from escrow (format *planned* in `backup-and-dr/04`, `docs/guides/escrow.md`), at the paths in
  [On pve1](#on-pve1)
- Neither: [Nothing escrowed](#nothing-escrowed)
- Permissions, as in the [pve1 guide](./pve1.md):
```bash
chmod 700 /root/secrets /root/ca/private /root/ca/intermediate/private /root/ssh/public
chmod 400 /root/secrets/age.* /root/secrets/*.yaml.age /root/secrets/*_id_ed25519.pub
chmod 600 /root/secrets/*.yaml
chmod 400 /root/ca/private/ca.key.pem /root/ca/intermediate/private/*.key.pem
chmod 400 /root/ssh/ca_ssh_key /root/ssh/ca_ssh_host_key
```

### 10. SSH: root key and host certs
```bash
sudo su
# root's client key, no passphrase: pve1's scripts use it unattended. Asks for the ca_ssh_key passphrase
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
ssh-keygen -s /root/ssh/ca_ssh_key -I pve1 -n manualadmin,autoadmin -V +395d /root/.ssh/id_ed25519.pub
# Trust the host CA before contacting other hosts; same line ssh_cert_gen.sh writes
echo "@cert-authority *.janedoe.com $(cat /root/ssh/ca_ssh_host_key.pub)" > /etc/ssh/ssh_known_hosts
# Signs pve1's new host key and refreshes the rest; needs pve2, vpnsvcs, websvcs, devtop and router up
/root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen.sh
```
- `ssh_cert_gen_windows.sh` isn't needed: the gaming VM's host cert and the CA are unchanged

### 11. Host services
- CA chain in pve1's own trust store (the `upload pve1` step of [CA infra](./pve1.md#ca-infra)):
```bash
cd /root/ca
/root/homelab-rendered/src/base/debian/send_files.sh intermediate/certs/ca-chain.cert.pem | ssh autoadmin@pve1 install_ca
```
- [pve1 guide, ACME Certificates](./pve1.md#acme-certificates): `traefik-certs-dumper`,
  `mkdir -p /root/acme`
- [pve1 guide, Notifications](./pve1.md#notifications): msmtp, the AppArmor edit, `cert_notifier`;
  skip creating the Gmail account
- [Proxmox guide](./proxmox.md): VM management (`vm_watchdog`), Networking (HA services, ufw),
  Monitoring (node_exporter and its ufw rule, `api_ro` user, metric server)

### 12. Certificates
```bash
/root/homelab-rendered/src/nodes/pve1/certificates/acme_transfer.sh
```
- Refills `/root/acme`, installs pve1's `pveproxy` cert, pushes certs to pve2, pbs2 and the router,
  re-pins the `pbs2` fingerprint
- Self-signed service certs live on the VMs; no re-issue

### 13. Backups and verification
- `/root/homelab-rendered/src/nodes/pve1/install_svcs.sh backup_orchestrator` if step 9 didn't, then
  one run: `systemctl start backup_orchestrator`
- Check:
  - Login at `https://auth.janedoe.com` (Authelia, LLDAP, Postgres)
  - `ssh manualadmin@pve1` from the workstation, no host-key prompt
  - `pvesm status` on pve1 shows `pbs2` active
  - `systemctl status cert_notifier.timer vm_watchdog node_exporter backup_orchestrator.timer --no-pager`
- Power pve2 back down: `ssh autoadmin@pve2 shutdown`

### Router without a VM backup
- Recreate the VM ([debugging, Recreate the VM](../debugging.md#recreate-the-vm)) and install
  pfSense ([router guide](./router.md#install-pfsense))
- Restore `config.xml` under Diagnostics >> Backup & Restore, from Auto Config Backup (needs the ACB
  device key and encryption password) or escrow; offline decryption: [Decrypt a config
  backup](../debugging.md#decrypt-a-config-backup)
- Not in `config.xml`, restore by hand:
  - `/root/router-src` and the dispatcher ([router guide, Automation](./router.md#automation))
  - `/root/pve2_mac_address.txt` ([pve2 guide, Automation](./pve2.md#automation))
  - `/root/pfsense-import-certificate.php` ([router guide, Certificate](./router.md#certificate))

## Partial loss

### Only the AGE key is lost
- From escrow or the PBS host backup: restore `age.txt`/`age.pub` and stop
- Otherwise the SOPS files on pve1 are unreadable, but each host's `secrets.yaml.age` is also
  encrypted to the host's key. Rebuild from those
- New key:
```bash
ssh manualadmin@pve1
sudo su
cd /root/secrets
mkdir -p lost && mv age.* ./*.yaml lost/
age-keygen -o age.txt
age-keygen -y age.txt > age.pub
chmod 400 age.*
export SOPS_AGE_RECIPIENTS=$(cat /root/secrets/age.pub)
export SOPS_AGE_KEY_FILE=/root/secrets/age.txt
```
- For each host (websvcs needs pve2 on); plaintext stays in RAM (`/dev/shm`):
```bash
host=secsvcs
umask 077
ssh -t "manualadmin@${host}" 'umask 077; sudo age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age > /dev/shm/secrets.yaml'
scp "manualadmin@${host}:/dev/shm/secrets.yaml" "/dev/shm/${host}.yaml"
ssh "manualadmin@${host}" 'rm /dev/shm/secrets.yaml'
sops -e "/dev/shm/${host}.yaml" > "/root/secrets/${host}.yaml"
rm "/dev/shm/${host}.yaml"
chmod 600 "/root/secrets/${host}.yaml"
# Re-encrypts to the new key + host key and redistributes; save and quit the editor
/root/homelab-rendered/src/nodes/pve1/secret_update.sh "$host"
```
- `secret_update.sh` needs each host's sudo password; they're in the maintainer's offline copy
  (`auth/08`), not SOPS
- If the host's SSH is broken, decrypt through the guest agent on its Proxmox host (pve1: secsvcs,
  homesvcs; pve2: websvcs), copy to pve1's `/dev/shm`, and continue from `sops -e`:
```bash
umask 077
qm guest exec VMID -- age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age \
  | jq -r '."out-data"' > /dev/shm/HOST.yaml
```
- `pve1.yaml` has no host copy. Recreate it with `sops /root/secrets/pve1.yaml` from
  `src/nodes/pve1/secrets_template.yaml`:
  - a new Gmail app password ([Notifications](./pve1.md#notifications))
  - a new `api_ro` password on PBS ([Proxmox guide, Monitoring](./proxmox.md#monitoring))
  - a new PBS token ([Proxmox guide, Backups](./proxmox.md#backups))
  - MaxMind keys from the MaxMind account
- `rm -rf /root/secrets/lost` once every host is done

### Only the private CA is lost
- Not urgent: service certs and the chain live on the VMs and work until they expire (395 days);
  only issuing is blocked
- Rebuild before the next [yearly renewal](../maintenance.md#refresh-certificates), in one sitting:
  services reject each other until all have the new chain
- Follow [CA infra](./pve1.md#ca-infra) in full: new root and intermediate, new passphrases,
  `openssl.cnf` from the rendered `src/nodes/pve1/certificates/openssl.{root,intermediate}.cnf`. Its
  `upload` loop installs the chain on every host
- Re-issue and redistribute every service key and cert:
```bash
/root/homelab-rendered/src/nodes/pve1/certificates/self_signed_key_gen.sh
/root/homelab-rendered/src/nodes/pve1/certificates/self_signed_cert_gen.sh
```
- Restart the secure services on secsvcs, homesvcs and websvcs, as the script asks
- Browser TLS is Let's Encrypt; if you added the private CA to a device's trust store by hand,
  replace it there too

### Only the SSH CA is lost
- Not urgent: hosts and clients trust the old CA, so existing certs work until they expire (395
  days); only signing is blocked
- New CA keys ([CA certs](./pve1.md#ca-certs)), with a new passphrase for `ca_ssh_key`
- Re-sign and redistribute everything, then the gaming VM
  ([Maintenance](../maintenance.md#refresh-certificates)):
```bash
/root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen.sh
ssh autoadmin@router start_pve2
ssh autoadmin@pve2 start_gaming_vm
/root/homelab-rendered/src/nodes/pve1/certificates/ssh_cert_gen_windows.sh
```
- Expect host-key prompts: pve1 trusts the new host CA before the script reaches every host
- Replace the `@cert-authority` line in `~/.ssh/known_hosts` on the workstation and other clients
  with the one the script prints

### Only vars.yml is lost
- Take it from the newest `/root/backups/repo/homelab-*.tar.gz` on pve1 (`vars.yml` is in the
  archive root), the PBS host backup, or escrow
- None of those: reconstruct it by diffing a render of the template against a host's
  `/root/homelab-rendered`, rendered with the real values at the last deploy. A host holds only
  its own `src/` paths, so diff several (pve1 and each container VM) to cover every value
```bash
# On the workstation, repo root, ideally at the last deployed commit
cp vars.template.yml vars.yml
work=$(mktemp -d)
tools/render_src.sh "$work/homelab-template"
ssh -t manualadmin@pve1 'sudo tar -C /root -czf /tmp/homelab-rendered.tgz homelab-rendered && sudo chown manualadmin /tmp/homelab-rendered.tgz'
scp manualadmin@pve1:/tmp/homelab-rendered.tgz "$work/"
ssh manualadmin@pve1 'rm /tmp/homelab-rendered.tgz'
tar -C "$work" -xzf "$work/homelab-rendered.tgz"
diff -r "$work/homelab-template" "$work/homelab-rendered"
```
- Edit `vars.yml` and repeat until the `diff` is empty, then `rm -rf "$work"`. A value no template
  uses can't be recovered, but nothing needs it

### Nothing escrowed
Neither escrow nor the PBS host backup can supply the trust roots. Do steps 1–8, then in place of
step 9:
1. SSH CA (run `ssh_cert_gen.sh` once, not once per section):
   - New `ca_ssh_key` and `ca_ssh_host_key`: the first two `ssh-keygen` blocks of [CA
     certs](./pve1.md#ca-certs); skip its root key and `ssh_cert_gen.sh`
   - Step 10 as written; with a new CA, `ssh_cert_gen.sh` asks for each host's password, as on the
     original install
   - The gaming VM's cert is from the old CA: also run the `start_pve2` / `start_gaming_vm` /
     `ssh_cert_gen_windows.sh` block from [Only the SSH CA is lost](#only-the-ssh-ca-is-lost), and
     replace the `@cert-authority` line on clients
2. AGE key: [Only the AGE key is lost](#only-the-age-key-is-lost), including `pve1.yaml`; collect
   each `<host>_id_ed25519.pub` again first ([pve1 guide, Secrets](./pve1.md#secrets))
3. Private CA: [Only the private CA is lost](#only-the-private-ca-is-lost)
4. Continue with steps 11–13
