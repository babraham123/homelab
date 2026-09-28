# pve1 disaster recovery
What to keep off pve1, and the order of operations when its SSD dies or one of its trust roots (AGE key, private CA, SSH CA, `vars.yml`) is lost. pve1 is the one host that restoring VMs can't bring back: the private CA, SSH CA, AGE key, ACME distribution and secret provisioning all live on the Proxmox host itself, outside every VM backup.

> **Current state:** nothing on the pve1 *host* is backed up. PBS (`pbs2` on pve2) holds the pve1 *VMs* (router, secsvcs, homesvcs), and only from runs where pve2 happened to be on. Until the escrow bundle exists, a dead SSD means doing the [AGE key](#only-the-age-key-is-lost), [CA](#only-the-private-ca-is-lost) and [SSH CA](#only-the-ssh-ca-is-lost) scenarios together; see [Nothing escrowed](#nothing-escrowed).
>
> Tickets referenced as `backup-and-dr/NN` are in `planning/backup-and-dr/issues/`. Anything marked *planned* depends on one of them and does not exist yet.

## What must exist off-box
This is the canonical list: `backup-and-dr/04` escrows it and `backup-and-dr/01`/`05` back it up. "Covered by":
- **PBS VM backup**: inside a VM disk that PBS backs up today.
- **Escrow**: the escrow bundle, *planned* (`backup-and-dr/04`).
- **Repo backup**: encrypted repo tarball on pve1, *planned* (`backup-and-dr/05`).
- **Regenerate**: derived; rebuild it with the script or guide section listed.

### On pve1

| Path on pve1 | What | Covered by | If lost |
|---|---|---|---|
| `/root/secrets/age.txt`, `age.pub` | AGE identity; every SOPS file and every host's `secrets.yaml.age` is encrypted to it | Escrow | [Only the AGE key is lost](#only-the-age-key-is-lost) |
| `/root/secrets/pve1.yaml` | pve1's own secrets: `msmtp_password`, `pbs2_api_password`, MaxMind keys | Escrow | No other copy; re-enter by hand from `src/pve1/secrets_template.yaml` |
| `/root/secrets/{secsvcs,homesvcs,websvcs}.yaml` | SOPS source of each host's secrets | Escrow | Rebuild from the host's own copy ([AGE scenario](#only-the-age-key-is-lost)) |
| `/root/secrets/<host>.yaml.age` | per-host `age` copy pushed to `/etc/opt/secrets/secrets.yaml.age` | Regenerate | `secret_update.sh <host>` |
| `/root/secrets/<host>_id_ed25519.pub` | host recipient key | Regenerate | re-`scp` from the host ([pve1 guide](./pve1.md#secrets)) |
| `/root/ca/private/ca.key.pem`, `certs/ca.cert.pem`, `index.txt`, `serial`, `crlnumber` | root CA | Escrow | [Only the private CA is lost](#only-the-private-ca-is-lost) |
| `/root/ca/intermediate/private/intermediate.key.pem`, `certs/intermediate.cert.pem`, `certs/ca-chain.cert.pem`, `index.txt`, `serial`, `crlnumber`, `crl/` | intermediate CA | Escrow | same |
| `/root/ca/intermediate/private/*.janedoe.com.key.pem`, `certs/`, `csr/` | per-service keys, certs and CSRs | Escrow (part of `/root/ca`) | `self_signed_key_gen.sh` + `self_signed_cert_gen.sh` |
| `/root/ca/openssl.cnf`, `/root/ca/intermediate/openssl.cnf` | CA config | Regenerate | rendered `src/certificates/openssl.{root,intermediate}.cnf` |
| `/root/ssh/ca_ssh_key`, `ca_ssh_key.pub` | SSH user CA: signs client keys for `manualadmin`/`autoadmin` | Escrow | [Only the SSH CA is lost](#only-the-ssh-ca-is-lost) |
| `/root/ssh/ca_ssh_host_key`, `ca_ssh_host_key.pub` | SSH host CA: behind every `@cert-authority` line | Escrow | same |
| `/root/ssh/known_hosts`, `public/`, `date_ssh_certs*.txt` | host pubkeys and certs, `@cert-authority` line, renewal timestamps | Regenerate | `ssh_cert_gen.sh`, `ssh_cert_gen_windows.sh` |
| Passphrases of `ca.key.pem`, `intermediate.key.pem`, `ca_ssh_key` | not files; asked for at signing time | Offline copy held by the maintainer; a better home is `auth/08` | the escrowed keys are useless without them |
| `/root/acme/` | copies of each Traefik's `acme.json`, dumped certs, `pbs2_cert_info.txt`, `date_acme_certs.txt` | Regenerate | `acme_transfer.sh` |
| `/root/.ssh/id_ed25519`, `id_ed25519-cert.pub` | root's client key, signed as `manualadmin,autoadmin`; every pve1 script SSHes with it | Regenerate | new key + re-sign ([step 10](#10-ssh-root-key-and-host-certs)) |
| `/etc/pve/storage.cfg`, `/etc/pve/priv/storage/pbs2.*` | `pbs2` storage entry and its credentials | Escrow (`/etc/pve` tarball) | re-add the storage ([step 3](#3-reconnect-the-pbs-storage)) |
| `/etc/pve/jobs.cfg`, `user.cfg`, `qemu-server/*.conf` | backup jobs, `api_ro` user, VM configs | Escrow (`/etc/pve` tarball); VM configs are also inside each PBS VM backup | VM configs return with `qmrestore`; recreate jobs and users ([Proxmox guide](./proxmox.md#backups)) |
| `/etc/network/interfaces`, `/etc/resolv.conf` | host network | Regenerate | from `src/pve1/interfaces.j2`, `src/pve1/resolv.conf.j2` |
| `/root/homelab-rendered/` | rendered repo | Regenerate | `tools/deploy_src.sh` from the workstation |
| `/etc/msmtprc`, `/usr/local/bin/{msmtp_password,cert_notifier,vm_watchdog}.sh`, their systemd units, the msmtp AppArmor edit, node_exporter | host services | Regenerate | [pve1 guide](./pve1.md#notifications), [Proxmox guide](./proxmox.md#vm-management) |
| `/root/backups/repo/` (*planned*) | encrypted repo tarballs | Escrow | `backup-and-dr/05` |

### Elsewhere

| Where | What | Covered by | If lost |
|---|---|---|---|
| `vars.yml` on the workstation | every personal value the render needs | nothing today (`tools/backup_src.sh` is manual and unencrypted); *planned*: Repo backup, Escrow | [Only vars.yml is lost](#only-varsyml-is-lost) |
| `/etc/opt/traefik/certificates/acme.json` on secsvcs, homesvcs, websvcs | Let's Encrypt account key + certs | PBS VM backup | Traefik re-issues on start (rate limits apply) |
| `/etc/opt/olive_tin/ssh/` on secsvcs | OliveTin's `autoadmin` key + cert | PBS VM backup | `ssh_cert_gen.sh` |
| `/etc/opt/secrets/id_ed25519`, `secrets.yaml.age` on each host | host decryption key + that host's secrets | PBS VM backup | new key, re-collect pubkey, `secret_update.sh <host>` |
| pfSense `config.xml` | firewall, VLANs, DHCP leases, DNS | PBS VM backup (router VM), Auto Config Backup; *planned*: Escrow | [Router without a VM backup](#router-without-a-vm-backup) |
| ACB device key + encryption password | needed to pull an ACB backup onto a fresh pfSense | Offline copy held by the maintainer; see `auth/08` | ACB backups unusable |
| PBS datastore `backup1` on pve2 | every VM backup | nothing (single copy); *planned*: offsite (`backup-and-dr/03`) | rebuild VMs from the guides |

## Rebuild pve1 from bare metal
Assumes the SSD is replaced, pve2 and its PBS datastore are intact, and you have the escrow bundle and `vars.yml`. VM restore details beyond what's here are *planned* in `backup-and-dr/06`.

All four NICs belong to the router VM, so until it's back there is no LAN, DHCP, DNS or Wake-on-LAN. Work from pve1's local console (keyboard + monitor) until step 5.

### 1. Install Proxmox with a temporary link to pve2
- Install Proxmox as in the [router guide](./router.md#install-proxmox); the user and desktop steps can wait.
- At the installer's network screen, set the hostname to `pve1.janedoe.com`. The node name must be `pve1`: restored VM configs land under `/etc/pve/nodes/pve1/`, and `acme_transfer.sh` and `install_dispatcher` look the host up by that name. Renaming a node after step 4 orphans the restored VMs.
- On the same screen, pick the NIC in the port cabled to pve2 (pfSense's `igc2`) and give it a free static address on pve2's subnet, e.g. `192.168.2.250/24`, gateway `192.168.2.1`. The router's ports are assigned in PCI order: WAN, LAN (WiFi AP), pve2, LAN2 (switch). So pve2's port is the third Ethernet controller in `lspci -nn | grep -i ethernet`. For PCI address `BB:00.0` Linux names it `enp<N>s0`, where `N` is the bus number `BB` converted from hex to decimal (`03` → `enp3s0`, `0a` → `enp10s0`). Confirm with `ip -br link`: only the cabled ports show `UP`.
- Enable IOMMU and the vfio modules now (router guide, [Install pfSense](./router.md#install-pfsense), "Enable IOMMU / NIC passthrough"). The restored router VM can't start without them.

### 2. Power on pve2 by hand
`start_pve2` sends Wake-on-LAN from the router, which is down: press pve2's power button. Proxmox configures a static address at install, so pve2 comes up on `192.168.2.10` without DHCP, and PBS listens on `:8007`.

### 3. Reconnect the PBS storage
- With the escrow `/etc/pve` tarball: copy back only `storage.cfg`, `priv/storage/pbs2.*` and `jobs.cfg`. Leave `nodes/`, `local/` and the certs; they belong to the new install.
- Without it:
```bash
# On pve2's console: the PBS cert fingerprint
proxmox-backup-manager cert info | grep Fingerprint

# On pve1
pvesm add pbs pbs2 --server 192.168.2.10 --datastore backup1 --namespace pve1 \
  --username 'USER@REALM' --password 'PASSWORD' --fingerprint 'FINGERPRINT'
pvesm list pbs2
```
- The storage authenticates as `root@pam` today; `backup-and-dr/11` replaces it with a backup-only user. If the storage has an encryption key (`ls /etc/pve/priv/storage/pbs2.enc` on the old pve1), that file is required to restore anything and must be escrowed; `backup-and-dr/11` decides whether to use one.

### 4. Restore the VMs
Restore the router, secsvcs and homesvcs while the temporary link is up. Don't start them yet.
```bash
pvesm list pbs2    # newest backup per VMID; check the dates
qmrestore pbs2:backup/vm/VMID/TIMESTAMP VMID --storage local-lvm
```
Each backup carries its VM config: NIC passthrough (`hostpci0`–`hostpci3`), MAC addresses, startup order. Snapshots may be old: today's schedule only runs when pve2 is on (`backup-and-dr/01`). If the router backup is missing or broken, see [Router without a VM backup](#router-without-a-vm-backup).

### 5. Switch pve1 to its normal network and start the router
pve1 normally has no physical port: `vmbr0` has no bridge ports and pfSense is its gateway.
- The rendered tree isn't on pve1 yet, so write `/etc/network/interfaces` and `/etc/resolv.conf` by hand from `src/pve1/interfaces.j2` and `src/pve1/resolv.conf.j2`: `vmbr0` static `192.168.4.10/24`, gateway `192.168.4.1`, `bridge-ports none`; `search janedoe.com`, `nameserver 192.168.4.1`.
```bash
ifreload -a
qm start ROUTER_VMID
ping 192.168.2.10
```
- From a LAN client, open `https://192.168.1.1/`.

### 6. Start the remaining VMs
```bash
# pve1
qm start SECSVCS_VMID
qm start HOMESVCS_VMID
# pve2, if they aren't set to start at boot; step 10 needs them
qm start WEBSVCS_VMID
qm start DEVTOP_VMID
```
The VMs keep their MACs, so pfSense's static DHCP leases hand back the same IPs. Their state (Authelia, LLDAP, Postgres, Traefik's `acme.json`, `/etc/opt/secrets/`) is whatever the backup held, and they don't need the pve1 host to run. Smoke test: log in at `https://auth.janedoe.com`.

### 7. Base host setup
- Proxmox repos and the `manualadmin` user: [router guide](./router.md#install-proxmox).
- [Debian setup](./debian.md) up to, not including, "Homelab Repo".

### 8. Re-render and upload
```bash
# From the workstation. The old pve1 entries in known_hosts (from the original
# install, before the host CA) would otherwise make ssh refuse the new host key.
ssh-keygen -R pve1; ssh-keygen -R pve1.janedoe.com; ssh-keygen -R 192.168.4.10
# Repo root
tools/deploy_src.sh
```
pve1's new host key isn't CA-signed until step 10, so expect a first-connection prompt. `deploy_src.sh` doesn't stop on a failed host; check its output for `pve1 upload failed`. Then on pve1:
- [Debian setup, Automation](./debian.md#automation): `autoadmin` user and `install_dispatcher`.
- [pve1 guide, Configs](./pve1.md#configs): jinjanator, yq.
- [pve1 guide, Secrets](./pve1.md#secrets): the first block only (age, sops, the shell exports). Skip `age-keygen`.

### 9. Restore the trust roots
The bundle format is decided in `backup-and-dr/04` (*planned*, `docs/guides/escrow.md`). Put everything back at the paths in [On pve1](#on-pve1), with the permissions from the [pve1 guide](./pve1.md):
```bash
chmod 700 /root/secrets /root/ca/private /root/ca/intermediate/private /root/ssh/public
chmod 400 /root/secrets/age.* /root/secrets/*.yaml.age /root/secrets/*_id_ed25519.pub
chmod 600 /root/secrets/*.yaml
chmod 400 /root/ca/private/ca.key.pem /root/ca/intermediate/private/*.key.pem
chmod 400 /root/ssh/ca_ssh_key /root/ssh/ca_ssh_host_key
```
No escrow: see [Nothing escrowed](#nothing-escrowed).

### 10. SSH: root key and host certs
```bash
sudo su
# root's client key, signed with the user CA (asks for the ca_ssh_key passphrase)
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
ssh-keygen -s /root/ssh/ca_ssh_key -I pve1 -n manualadmin,autoadmin -V +395d /root/.ssh/id_ed25519.pub
# Trust the host CA before contacting other hosts; same line ssh_cert_gen.sh writes
echo "@cert-authority *.janedoe.com $(cat /root/ssh/ca_ssh_host_key.pub)" > /etc/ssh/ssh_known_hosts
# Signs pve1's new host key and refreshes the rest; needs pve2, vpn, websvcs, devtop and router up
/root/homelab-rendered/src/certificates/ssh_cert_gen.sh
```
The key has no passphrase because pve1's scripts use it without a prompt ([pve1 guide](./pve1.md#ca-certs)). `ssh_cert_gen_windows.sh` isn't needed: the gaming VM's host cert and the CA are unchanged.

### 11. Host services
- CA chain in pve1's own trust store (the `upload pve1` step of [CA infra](./pve1.md#ca-infra)):
```bash
cd /root/ca
scp intermediate/certs/ca-chain.cert.pem autoadmin@pve1:/home/autoadmin
ssh autoadmin@pve1 install_ca
```
- [pve1 guide, ACME Certificates](./pve1.md#acme-certificates): install `traefik-certs-dumper`, `mkdir -p /root/acme`.
- [pve1 guide, Notifications](./pve1.md#notifications): msmtp, the AppArmor edit, `cert_notifier`. Skip creating the Gmail account.
- [Proxmox guide](./proxmox.md): VM management (`vm_watchdog`), Networking (HA services, ufw), Monitoring (node_exporter and its ufw rule, `api_ro` user, metric server).

### 12. Certificates
```bash
/root/homelab-rendered/src/certificates/acme_transfer.sh
```
Refills `/root/acme`, installs pve1's `pveproxy` cert, pushes certs to pve2, pbs2 and the router, and re-pins the `pbs2` fingerprint on pve1. Self-signed service certs don't need re-issuing; they live on the VMs.

### 13. Backups and verification
- If step 3 restored `jobs.cfg`, the backup job is already back. Otherwise recreate it ([Proxmox guide, Backups](./proxmox.md#backups), "PVE setup"), until the orchestrator replaces it (*planned*, `backup-and-dr/01`, `02`). Either way, run it once now.
- Check:
  - Login at `https://auth.janedoe.com` (Authelia, LLDAP, Postgres).
  - `ssh manualadmin@pve1` from the workstation, with no host-key prompt.
  - `pvesm status` on pve1 shows `pbs2` active.
  - `systemctl status cert_notifier.timer vm_watchdog node_exporter --no-pager`.
- Power pve2 back down: `ssh autoadmin@pve2 shutdown`.

### Router without a VM backup
- Recreate the VM with the settings in [debugging, Recreate the VM](../debugging.md#recreate-the-vm) and install pfSense ([router guide](./router.md#install-pfsense)).
- Restore `config.xml` under Diagnostics >> Backup & Restore, from Auto Config Backup (needs the ACB device key and encryption password) or from escrow. To read an encrypted backup offline: [Decrypt a config backup](../debugging.md#decrypt-a-config-backup).
- Files on the router's disk that `config.xml` doesn't carry: `/root/router-src` and the dispatcher ([router guide, Automation](./router.md#automation)), `/root/pve2_mac_address.txt` ([pve2 guide, Automation](./pve2.md#automation)), `/root/pfsense-import-certificate.php` ([router guide, Certificate](./router.md#certificate)).

## Partial loss

### Only the AGE key is lost
With the escrow bundle, restore `age.txt`/`age.pub` and stop. Once the escrow AGE recipient exists (*planned*, `backup-and-dr/04`), the escrow key can also decrypt every `*.yaml.age` directly.

Without it, the SOPS files on pve1 are unreadable, but each host can still decrypt its own `secrets.yaml.age`, which is encrypted to the host's key as well. Rebuild from those.
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
- For each of secsvcs, homesvcs, websvcs (websvcs needs pve2 on). Plaintext only touches RAM (`/dev/shm`):
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
/root/homelab-rendered/src/pve1/secret_update.sh "$host"
```
- The host sudo passwords are required: `secret_update.sh` installs the re-encrypted file over `ssh` with `sudo`. They're not in SOPS; they're in the maintainer's offline copy (`auth/08`). If only the *decrypt* half is a problem (e.g. the host's SSH is broken), pull the plaintext as root through the guest agent on the Proxmox host that runs the VM (pve1: secsvcs, homesvcs; pve2: websvcs), copy it to pve1's `/dev/shm`, and continue from `sops -e`:
```bash
umask 077
qm guest exec VMID -- age -d -i /etc/opt/secrets/id_ed25519 /etc/opt/secrets/secrets.yaml.age \
  | jq -r '."out-data"' > /dev/shm/HOST.yaml
```
- `pve1.yaml` has no host copy. Recreate it with `sops /root/secrets/pve1.yaml` from `src/pve1/secrets_template.yaml`: a new Gmail app password ([Notifications](./pve1.md#notifications)), a new `api_ro` password on PBS ([Proxmox guide, Monitoring](./proxmox.md#monitoring)), and MaxMind keys from the MaxMind account.
- `rm -rf /root/secrets/lost` once every host is done.

### Only the private CA is lost
Not an emergency: every service cert and the CA chain live on the VMs and keep working until they expire (395 days). Only issuing is blocked. Rebuild before the next [yearly renewal](../maintenance.md#refresh-certificates), in one sitting, because services reject each other until all of them have the new chain.
- Follow [CA infra](./pve1.md#ca-infra) in full: new root and intermediate, new passphrases, `openssl.cnf` from the rendered `src/certificates/openssl.root.cnf` and `openssl.intermediate.cnf`. Its `upload` loop installs the new chain on pve1, pve2, vpn, secsvcs, homesvcs, websvcs and devtop.
- Re-issue and redistribute every service key and cert, including the chain in each service's cert directory:
```bash
/root/homelab-rendered/src/certificates/self_signed_key_gen.sh
/root/homelab-rendered/src/certificates/self_signed_cert_gen.sh
```
- Restart the secure services on secsvcs, homesvcs and websvcs, as the script asks.
- Browser-facing TLS is Let's Encrypt, and the repo doesn't install the private CA on client devices. If you added it to a laptop's trust store by hand, replace it there too.

### Only the SSH CA is lost
Also not an emergency: hosts keep trusting the old `ca_ssh_key.pub` and clients the old `@cert-authority` line, so existing host and client certs work until they expire (395 days). Only signing is blocked.
- Generate new CA keys ([CA certs](./pve1.md#ca-certs)), with a new passphrase for `ca_ssh_key`.
- Re-sign and redistribute everything, then the gaming VM (sequence from [Maintenance](../maintenance.md#refresh-certificates)):
```bash
/root/homelab-rendered/src/certificates/ssh_cert_gen.sh
ssh autoadmin@router start_pve2
ssh autoadmin@pve2 start_gaming_vm
/root/homelab-rendered/src/certificates/ssh_cert_gen_windows.sh
```
- Expect host-key prompts during `ssh_cert_gen.sh`: pve1 switches to the new host CA first, while hosts the script hasn't reached yet still present certs from the old one.
- Replace the old `@cert-authority` line in `~/.ssh/known_hosts` on the workstation and other clients with the one the script prints.

### Only vars.yml is lost
- *Planned*: decrypt the newest `/root/backups/repo/homelab-src-*.tar.gz.age` on pve1 with `age.txt` (`backup-and-dr/05`), or take the escrow copy (`backup-and-dr/04`).
- Today: reconstruct it from a rendered tree. Every host's `/root/homelab-rendered` (docs included) was rendered with the real values at the last deploy; diffing it against a render of the template pairs each placeholder with its real value.
```bash
# On the workstation, repo root, ideally at the last deployed commit
cp vars.template.yml vars.yml
tools/render_src.sh /tmp/homelab-template
ssh -t manualadmin@pve1 'sudo tar -C /root -czf /tmp/homelab-rendered.tgz homelab-rendered && sudo chown manualadmin /tmp/homelab-rendered.tgz'
scp manualadmin@pve1:/tmp/homelab-rendered.tgz /tmp/
ssh manualadmin@pve1 'rm /tmp/homelab-rendered.tgz'
mkdir -p /tmp/homelab-real && tar -C /tmp/homelab-real -xzf /tmp/homelab-rendered.tgz
diff -r /tmp/homelab-template /tmp/homelab-real/homelab-rendered
```
- Edit `vars.yml` and repeat the render + `diff` until it's empty, then `rm -rf /tmp/homelab-*`. A value no template uses can't be recovered, but nothing needs it.

### Nothing escrowed
Today's situation for a dead SSD. Do the bare-metal steps 1–8, then, in place of step 9:
1. SSH CA. Run `ssh_cert_gen.sh` once, not once per section:
   - New `ca_ssh_key` and `ca_ssh_host_key` only: the first two `ssh-keygen` blocks of [CA certs](./pve1.md#ca-certs). Skip that section's root key and `ssh_cert_gen.sh`.
   - Step 10 as written. With a new CA, `ssh_cert_gen.sh` asks for each host's password on its first run, as on the original install.
   - The gaming VM's host cert is from the old CA, so also run the `start_pve2` / `start_gaming_vm` / `ssh_cert_gen_windows.sh` block from [Only the SSH CA is lost](#only-the-ssh-ca-is-lost), and replace the `@cert-authority` line on the workstation and other clients.
2. AGE key: [Only the AGE key is lost](#only-the-age-key-is-lost), including `pve1.yaml`. Collect each `<host>_id_ed25519.pub` again first ([pve1 guide, Secrets](./pve1.md#secrets)).
3. Private CA: [Only the private CA is lost](#only-the-private-ca-is-lost).
4. Continue with steps 11–13.
