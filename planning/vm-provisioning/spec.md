# VM provisioning with cloud-init

Status: deferred. No issues; pick this up the next time a Debian VM is created, instead of
following `docs/guides/vm.md` and the first half of `docs/guides/debian.md` by hand.

## Problem

A new Debian node is built by hand: the graphical installer, then ~150 lines of copy-paste shell
from `debian.md` and `podman.md` (users, packages, sshd, ufw, timezone, hostname, zsh, the
manualadmin key pair that doubles as the node's AGE identity). Nothing in the repo records those
steps in a runnable form, and every new VM repeats them.

## Alternatives considered

| Option | Verdict |
| --- | --- |
| pyinfra (or Ansible) from the laptop as `manualadmin` with the sudo password | Consistent with ADR 0005 for the bootstrap only; the node-side `install_*` scripts must keep running from the dispatcher, so it would be a second tool for one phase. A deleted `ansible` branch says this was tried once |
| Debian preseed | Automates the installer, fiddly to iterate; the cloud image makes the installer unnecessary |
| Proxmox template + clone (Packer) | A golden image to keep updated, for four VMs |
| Bash `bootstrap.sh` run once after the first upload | Cheapest; still needs the manual OS install first. Keeps the steps cloud-init can't express |
| **cloud-init on the Debian generic cloud image** | Replaces the installer and the first-boot shell with one rendered YAML file; no new tool on the laptop or the node. Chosen |

## Design

One shared config, `src/base/debian/cloud-init.yml.j2`, rendered like every other template and
checked by yamllint. PVE nodes already receive `src/base/`, so it lands on pve1 and pve2 at
`/root/homelab-rendered/src/base/debian/cloud-init.yml`. It is delivered as Proxmox
**vendor-data**; a tiny per-VM **user-data** carries what differs per node. Linode takes only
user-data, so vpnsvcs gets the two concatenated by hand.

### Shared config (vendor-data)

| Step in the guides today | cloud-init |
| --- | --- |
| Graphical install, ext4 single partition, no LVM | Gone: `debian-13-genericcloud-amd64.qcow2` is that layout, UEFI-ready; `growpart` fills the disk |
| `manualadmin` in `sudo`, zsh; password SSH until the CA cert lands | `users:` with `groups: sudo`, `shell: /bin/zsh`, `ssh_authorized_keys` from a new `manualadmin_ssh_pubkey` var in `vars.yml`; `ssh_pwauth: false` |
| `adduser autoadmin`, root-owned home, no sudo group | `users:` with `lock_passwd: true`; `runcmd` `chown root:root /home/autoadmin && chmod 755`, since cloud-init creates the home user-owned |
| `adduser node_exporter --system` plus group | `users:` with `system: true`, `shell: /usr/sbin/nologin`, `no_create_home: true` |
| contrib/non-free in `sources.list` | `write_files` a deb822 `/etc/apt/sources.list.d/nonfree.sources` with `Components: contrib non-free non-free-firmware` only; works whether the image ships `sources.list` or `debian.sources` |
| apt update/upgrade, base packages, python3, age jq gnupg2 zstd | `package_update`, `package_upgrade`, `packages:`, plus `qemu-guest-agent` (not in the image) |
| Uncomment `-updates` in `50unattended-upgrades` | `write_files` `/etc/apt/apt.conf.d/52unattended-upgrades-local` with an `Origins-Pattern` entry |
| `timedatectl set-timezone` | `timezone: {{ personal.timezone }}` |
| `PermitRootLogin no` | `write_files` `/etc/ssh/sshd_config.d/10-homelab.conf`; `disable_root: true` is the image default |
| `ufw allow ssh; ufw enable` | `runcmd`; `install_network.sh` resets the rules later anyway |
| `chsh` root, `root.zshrc`, `aliases.zsh`, `functions.zsh` | `write_files` with the repo files inlined through Jinja. oh-my-zsh and the p10k wizard are interactive: stay in the guide, or drop p10k |
| `ssh-keygen` for manualadmin (the node's AGE identity), `/etc/opt/secrets` 700, `/root/backups` 700 | `runcmd`: `ssh-keygen -N ''` as manualadmin, `install -d -m 700`, copy the pair. `final_message` prints the public key, replacing the `scp` step in `pve1.md` |

Optional: the alvistack podman repo, its pin file and the trivy repo as `apt: sources:`, which
handles keys cleanly, shrinking `install_podman.sh` and the `image_updater` case. Not required.

### Per-VM config (user-data)

Written by the create script on the PVE host: `hostname`, `fqdn` (`<node>.{{ site.url }}`),
`manage_etc_hosts: true`, `chpasswd` with manualadmin's hash, and `instance-id` in meta-data.

The hash comes from `read -s` plus `mkpasswd -m sha-512` at create time, never from `vars.yml`: a
hash there would land in the rendered tree on every node.

### Create script

A `create_vm` case in pve1's and pve2's `commands.sh`, driven by a `vm:` block per node in
`inventory.yml` (VMID, MAC, cores, memory, disk size), or by arguments if the dispatcher stays
parameterless and the script is run by hand as root. It:

1. Downloads the qcow2 and checks it against Debian's `SHA512SUMS` (a `fetch_pinned` variant).
1. `qm create` with the `vm.md` settings: q35, OVMF with EFI disk, VirtIO SCSI single, SSD
   emulation and discard, CPU `host`, ballooning; `--net0 virtio=<MAC>,bridge=...` so the
   pfSense static lease and DNS record can be written from the same MAC; `--agent 1`.
1. `qm importdisk`, `qm disk resize`.
1. Copies the rendered `cloud-init.yml` to `/var/lib/vz/snippets/`, writes `<node>-user.yml`,
   then `qm set --cicustom vendor=local:snippets/cloud-init.yml,user=local:snippets/<node>-user.yml
   --ipconfig0 ip=dhcp`.

One-time prerequisite per PVE host: `pvesm set local --content iso,vztmpl,backup,snippets`.

### Hand-off

After the first boot the flow is unchanged: pfSense static lease and DNS record, `secret_update.sh`
on pve1 with the printed public key, `tools/upload_src.sh`, `install_dispatcher`, then
`install_<svc>`. `install_podman.sh`, `install_render_tools.sh` and `install_network.sh` stay
as they are.

## Risks and open points

- **Vendor/user merge.** Scalars in user-data override vendor-data reliably; list merging
  (`runcmd`, `packages`) across the two is not something to depend on. Every list stays in
  vendor-data.
- **Runs once.** cloud-init applies per `instance-id`; editing the template changes nothing on an
  existing VM. It provisions; it is not configuration management, and drift stays with the
  `install_*` scripts as today.
- **Secrets ordering.** The node's AGE recipient key exists at first boot, earlier than today, but
  `secret_update.sh` on pve1 must still run before any `install_<svc>`. Same order, one fewer
  manual step.
- **vpnsvcs.** Linode user-data, `Port 2202`, 711 on `/etc/opt/secrets`: the vpnsvcs guide keeps a
  short delta section.
- **Not covered.** pve1 and pve2 themselves (bare-metal Proxmox with NIC, GPU and SATA
  passthrough), the router and the gaming VM.

## Proof step

Before adopting: a throwaway VMID on pve2, `cloud-init status --long` and
`/var/log/cloud-init.log` clean, then `upload_src.sh` and `install_dispatcher` against it to confirm
the hand-off point, then destroy it.
