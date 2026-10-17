# auth/08 research notes: where human-held secrets live, and which can go away

Research for [08-password-management-research.md](issues/08-password-management-research.md), checked
2026-10-12 against the repo at `edfad53`. Every claim about the repo cites a file and line. Every
other claim cites a URL, collected under [Sources](#8-sources). INFERENCE marks my own reading;
UNVERIFIED marks a claim I couldn't confirm in a primary source.

Versions that matter:

| Component | Version |
| --- | --- |
| Debian 13 trixie: VMs and both Proxmox hosts (`docs/guides/proxmox.md.j2:21-22`) | OpenSSH 10.0p1 [D1]; `age` 1.2.1 [D2] |
| Proxmox | VE 9.x; PBS 4.x on pve2's host OS (`docs/guides/proxmox.md.j2:200-205`) |
| SOPS | installed from GitHub latest (`docs/guides/pve1.md.j2:60-61`); 3.13.3 today [S1] |
| Vaultwarden | 1.37.4 [V1] |
| macOS bundled ssh | 10.3p1, built without FIDO support [M1] |

## 1. Current state

### The human-held secrets

The ticket's list is incomplete. The repo also prompts for, or depends on, the secrets marked *new*
below.

| Secret | Where the repo uses it | Used how often |
| --- | --- | --- |
| `ca.key.pem` passphrase (root X.509 CA) | `docs/guides/pve1.md.j2:124-125` | Once per intermediate: `default_days 3650` (`openssl.root.cnf.j2:34`). No root CRL is generated anywhere (`gencrl` appears nowhere in `src/` or `docs/`) |
| `intermediate.key.pem` passphrase | `self_signed_cert_gen.sh.j2:20-21`, read once, then passed as `-passin "pass:$CA_PASS"` (`:28` and each later `openssl ca`) | Yearly (`docs/maintenance.md`, "Once a year") |
| `ca_ssh_key` passphrase (SSH user CA) | `docs/guides/pve1.md.j2:34-35`; `ssh_cert_gen.sh.j2:71,76,85` | Yearly, three signatures |
| `ca_ssh_host_key` | **No passphrase** (`docs/guides/pve1.md.j2:39-40`) | Yearly |
| `manualadmin` sudo password, each Debian node, pve1 and pve2 | `tools/upload_src.sh:45-51` (every deploy, every node); `secret_update.sh:27-37`; `docs/debugging.md:802-810` | Every deploy |
| Debian root password | Console login during install (`docs/guides/debian.md.j2:16-19`); `PermitRootLogin no` (`:55`) | Install only |
| Proxmox `root@pam` password, pve1 and pve2 (and PBS, which is pve2's root) | Web UI and console (`docs/guides/router.md.j2:21`, `docs/guides/proxmox.md.j2:16`) | Occasional |
| *new:* pve2's `root@pam` password, **stored in PVE** | `docs/guides/proxmox.md.j2:242-246`: pve2's `pbs2` storage logs in as `root@pam --password ROOT_PASSWORD`, so it sits in `/etc/pve/priv/storage/pbs2.pw` on pve2 | Every pve2 backup |
| pfSense `admin` password | `tools/upload_src.sh:20-21` (every deploy); `ssh_cert_gen.sh.j2:48` (`admin@router`); web UI | Every deploy |
| *new:* pfSense `autoadmin` password | `docs/guides/router.md.j2:298-301` | Never after setup |
| *new:* Debian `autoadmin` password | `adduser autoadmin` (`docs/guides/debian.md.j2:117`) | Never, see the bootstrap bug below |
| *new:* gaming VM Windows `admin` password | `tools/upload_src.sh:27-28`; `ssh_cert_gen_windows.sh.j2:17` | Rare |
| pfSense ACB device key and encryption password | `docs/guides/router.md.j2:112`; `docs/guides/pve1_recovery.md.j2:61,228-230` | Only when restoring the router without a VM backup |
| *new:* Vaultwarden master password, plaintext admin token | `planning/vaultwarden/issues/01-install-vaultwarden.md:174-180` | Daily / rare |

`docs/guides/pve1_recovery.md.j2:42,61,267-268` and backup-and-dr/09's last comment
(`09-pve1-disaster-recovery-guide.md:48-51`) already point at this ticket for the CA passphrases,
the ACB secrets and the sudo passwords.

### Findings in the current scripts

1. **The debugging recipe was already rewritten.** The `sops -d … | yq ".HOST_root_pswd"` version
   the ticket quotes was replaced in `b02f3a8` (the same commit that filed this ticket).
   `docs/debugging.md:802-810` now reads the password with `read -rs` and pipes it to `sudo -S`. It
   works, but it still needs a sudo password typed by hand. The ticket's premise ("the recipe
   doesn't work") is out of date. Its root cause stands: no store holds those passwords.
2. **The scripts' prompts say "root password" but mean manualadmin's own password**
   (`secret_update.sh:27`, `upload_src.sh:45`). By default sudoers "validates the invoking user's
   credentials, not the target user's (or root's)" [SU1]. Nothing in the repo sets `rootpw`.
3. **First-run `ssh_cert_gen.sh` no longer works on a host that doesn't trust the CA yet.**
   - `docs/guides/pve1.md.j2:48-49` says the first run "will ask you for the root password of
     various hosts". `pve1_recovery.md.j2:343` says the same for a rebuilt CA.
   - Since `da281e1`/`650a352` (2026-10-10/12), `install_ssh_ca` is `pve1_file_transfer: true`
     (e.g. `src/nodes/secsvcs/inventory.yml:39`), and `require_pve1`
     (`src/base/debian/dispatcher.sh.j2:25-33`) accepts only a certificate login with key ID `pve1`.
   - A host without `/etc/ssh/ca_ssh_key.pub` can't verify pve1's certificate, and autoadmin has no
     `authorized_keys` (root-owned home, `docs/guides/debian.md.j2:118-122`). So sshd falls back to
     autoadmin's *password*.
   - The `host_key` call (`ssh_cert_gen.sh.j2:31`) passes. `install_ssh_ca` (`:37`) is then refused,
     because `$SSH_USER_AUTH` holds no certificate.
   - Bootstrapping a new host or CA therefore takes a manual step as manualadmin (install
     `ca_ssh_key.pub` with sudo) that no guide documents. This is a real blocker for 09's "Nothing
     escrowed" path, independent of this ticket.
4. **`openssl ca -passin "pass:$CA_PASS"` puts the intermediate passphrase in the process's
   argv,** visible in `ps` and `/proc/*/cmdline`. OpenSSL: the `pass:` form "should only be used
   where security is not important" [O1]. Use `-passin fd:3` or `env:` instead
   (`self_signed_cert_gen.sh.j2:28` and each later `openssl ca`).
5. **pve1's root key is certified for `manualadmin`** (`ssh_cert_gen.sh.j2:71`). Only
   `secret_update.sh:10,25,28-37` uses that principal, and only to reach sudo. The workstation's
   key is certified the same way (`:85`), with no hardware backing; the guide makes it with plain
   `ssh-keygen -t ed25519` (`docs/guides/debian.md.j2:61`).
6. **SOPS in this repo already supports what option Q1-e needs.** SOPS 3.10.0 added age plugins,
   SSH recipients, passphrase-protected age identities and `SOPS_AGE_KEY_CMD` [S1]. The plugin
   code path is `plugin.NewRecipient`/`plugin.NewIdentity` in `age/keysource.go` [S2]. The
   comment at `secret_update.sh:21` ("SOPS doesn't support SSH keys") is stale. ADR 0004 still
   holds: SOPS files never go in this public repo, not even encrypted
   (`docs/adr/0004-sops-age-secrets.md`, Context).

### Hosts

- **Proxmox VE 9 on Debian 13:** pve1, pve2. PBS 4 runs on pve2's host, so PBS `root@pam` is pve2's
  Linux root.
- **Debian 13 VMs:** secsvcs, homesvcs (on pve1), websvcs, devtop (on pve2).
- **Debian VPS:** vpnsvcs (Linode).
- **pfSense:** router, a VM on pve1.
- **Windows:** gaming, on pve2.

## 2. Q1: where should the secrets live?

### Options

| | Availability when the homelab is down | Blast radius if the store leaks | Fit with backup-and-dr/04 escrow | Day-to-day friction | Cost |
| --- | --- | --- | --- | --- | --- |
| **a. Vaultwarden on secsvcs** | Logged-in, *locked* clients unlock offline, read-only [B1] [B2] [B3]. A logged-out client can't log in. New devices need Authelia (`SSO_ONLY`). Worst case: the escrowed export | Ciphertext under the master password (600k PBKDF2 / Argon2id) [B4]; server compromise alone doesn't decrypt. Lives on the same host it helps recover | Good: 04 already escrows a password-protected export and the admin token (`04-key-escrow-plan.md:44-46`). Decrypting the export needs some Bitwarden server (a laptop Vaultwarden works, INFERENCE) [B5] [V2] | Lowest: browser/phone autofill, already deployed | $0 |
| **b. Hosted Bitwarden** | Best: cloud, plus the same offline cache [B1] | Same zero-knowledge model [B4]; adds a third-party target | Same export path; emergency access needs Premium [B6] | Same clients as (a), so the same friction | $0 free; $19.80/yr Premium [B7] |
| **c. 1Password** | Cloud plus offline apps [P1]; SSO-unlock accounts have no general offline access [P2] | 2SKD: Secret Key + password, so a server breach can't be guessed offline [P3] | Emergency Kit is paper by design [P4]; 1PUX export is **unencrypted** [P5] and would need `age -p` | Low | ~$36-48/yr individual [P6] |
| **d. KeePassXC, escrowed** | Full: a file on every device and on the escrow sticks | KDBX4 + Argon2 [K1]; with a YubiKey HMAC-SHA1 challenge-response, the file alone is useless [K2] | Native: the `.kdbx` *is* the escrow artifact. A YubiKey backup needs the same HMAC secret programmed into two keys and kept on paper [K3] [Y1] | Highest: a second store to sync. No FIDO2 [K4] | $0, plus two YubiKeys |
| **e. SOPS/age file with a YubiKey identity** | Full, if the file sits on the workstation and the escrow sticks | age-plugin-yubikey keys live in PIV and can't be extracted [A1]. Add a second recipient for loss [A2] | Native: SOPS already escrows this way. A passphrase (scrypt) stanza must be the only stanza [A3], so the escrow recipient must be an X25519 identity that is itself `age -p` encrypted [A4] | High for humans: `sops -d` plus PIN/touch to read one password; no autofill | $0, plus two YubiKeys |

### Notes per option

- **a. Vaultwarden.**
  - **Bootstrap problem.** pve1's recovery needs some secrets before secsvcs is back (steps 1-5 of
    `pve1_recovery.md.j2`): pve2's console login, `pbs_client.key` and the PBS token, and the ACB
    secrets if the router backup is gone. Vaultwarden can't be the only copy of those. A device
    that was logged in and only *locked* still unlocks offline [B2] [B3]. Offline sessions may
    expire after 30 days (90 on mobile), per a 2022 Bitwarden blog post that the current help
    page doesn't repeat [B8].
  - **Restore.** A Vaultwarden restore is "stop, then replace each file or directory in the data
    dir" [V2]. With Postgres, the DB comes from `pg_dumpall` and `rsa_key*` from the volume
    (`01-install-vaultwarden.md:170-172`).
  - **Emergency access** exists and is on by default [V1]. The grantee must be on the same server
    (INFERENCE), so it doesn't help when the homelab is down.
- **b and c. Hosted.** Both are viable and solve availability outright. But they run against the
  architecture goal "No reliance on cloud providers, except a single cheap VPS"
  (`docs/architecture.md:10`), and Vaultwarden already gives the same client experience.
  1Password's export being plaintext is a mismatch with 04's encrypted bundle.
- **d. KeePassXC.** Technically the cleanest offline store. `keepassxc-cli show -a password -y 2`
  can feed a script [K5]. Rejected because a second human password store means two places to update
  on every rotation.
- **e. SOPS/age + YubiKey.** Already the right tool for *machine* secrets (ADR 0004). For ~15 human
  passwords read a few times a year, it adds YubiKey ceremony with no autofill. Where it does fit
  is the *escrow identity* of 04 item 3. SOPS 3.10+ accepts plugin recipients, so a YubiKey
  recipient can sit beside pve1's key [S1] [S2]. Debian's packaged age 1.2.1 lacks the plugin-free
  `age1tag` recipients of age 1.3 [A5] [D2].

## 3. Q2: can the passwords go away?

### sudo through the SSH agent (`pam_ssh_agent_auth`, `pam_rssh`): no

| | `pam_ssh_agent_auth` | `pam_rssh` |
| --- | --- | --- |
| Debian | Packaged as `libpam-ssh-agent-auth`: bookworm 0.10.3-4, trixie 0.10.3-11 [PA1]. Orphaned (QA Group), dropped from testing twice [PA2] | Not packaged [PR1]. Upstream builds RPMs only; v1.2.1, 2026-06 [PR2] |
| Upstream | Dormant: last commit 2021-02, last tag 0.10.4 (2019) [PA3] | Active [PR2] |
| OpenSSH certificates / CA | **No.** Issue #31 open since 2021. `-cert-v01` key types break the key parser (PR #49) [PA4] | **No.** Issue #29 "SSH CA Authorization" open [PR3] |
| sk keys | ecdsa-sk/ed25519-sk unsupported (#23). Destination-constrained agents break it (#44) [PA5] | Supports ED25519-SK/ECDSA-SK [PR4] |
| Needs | `auth sufficient pam_ssh_agent_auth.so file=…` in `/etc/pam.d/sudo`, `Defaults env_keep += "SSH_AUTH_SOCK"` [PA6] | `auth sufficient libpam_rssh.so`, the same `env_keep` [PR4] |

**Blockers:**

- **Neither honours the SSH CA.** Both need plain public keys per user in a root-owned file
  [PA6] [PR4], so "sudo trusts the same SSH CA" is impossible today.
- **Both need agent forwarding to every host.** ssh(1) warns that root on the remote host can use
  the forwarded agent's identities [SS1]. Here the workstation's identity is certified for
  `manualadmin,autoadmin` on *every* node (`ssh_cert_gen.sh.j2:85`). Forwarding it would let one
  compromised VM reach all the others.

### sudo without a password (NOPASSWD), gated by a hardware-backed login: yes

- `NOPASSWD` drops authentication per rule [SU1].
- sshd's certificate login becomes the only gate, which is safe if the key behind the manualadmin
  certificate can't be copied:
  - Generate the workstation key as `ed25519-sk`; YubiKey firmware 5.2.3+ [Y2].
  - Sign it with `-O verify-required`, so each login needs PIN plus touch [SS2].
  - FIDO private keys "cannot be exported from the authenticator hardware" [SS3].
- Malware on the workstation can keylog a sudo password today. A per-login PIN and touch is stronger
  than that, not weaker.
- **macOS:** Apple's bundled ssh is built without libfido2 and fails `-t ed25519-sk` ("No FIDO
  SecurityKeyProvider specified", tested on this Mac). Use Homebrew `openssh` [M1] [M2].
- **pve1's root key stays file-based,** because scripts use it unattended. It must lose the
  `manualadmin` principal, or root on pve1 gains passwordless root everywhere:
  - Change `ssh_cert_gen.sh.j2:71` to `-n autoadmin`.
  - Move `secret_update.sh`'s install step into a dispatcher command (`install_secrets`,
    `pve1_file_transfer: true`) that takes `secrets.yaml.age` on stdin, like the other
    `install_*` commands.
  - INFERENCE: pve1 can already replace any host's CA through `install_ssh_ca`, so root on pve1 is
    already root everywhere. This change keeps NOPASSWD from widening that further.

### Locking root and manualadmin passwords

| Host | Lock? | Why it's safe / what breaks | Break glass |
| --- | --- | --- | --- |
| Debian VMs (secsvcs, homesvcs, websvcs, devtop) | **Yes**: `passwd -l root`, `passwd -l manualadmin` | `passwd -l` doesn't disable key logins [L1]. sshd checks for locked accounts only when `UsePAM no` [L2], and Debian ships `UsePAM yes` [L3] | From the Proxmox host: `qm guest exec` (`docs/debugging.md` "Run commands via the guest agent"); or `qm terminal`/noVNC with `SYSTEMD_SULOGIN_FORCE=1` [L4] or `init=/bin/bash` on the kernel line. `sulogin --force` gives a root shell when root is locked [L5] |
| New Debian installs | Leave root's password empty in the installer: root is disabled and the first user gets sudo [L6]. Set a throwaway manualadmin password, then lock it once the CA is installed | | as above |
| vpnsvcs (Linode) | Yes, as the VMs | | Linode's LISH console / rescue mode (UNVERIFIED here). Its access is the Linode account, so that account's password and 2FA join the store |
| pve1, pve2 (Proxmox VE 9) | **manualadmin: yes. root: no** | `root@pam` authenticates through Linux PAM [PX1], so locking root ends web login as root. Some settings are hard-coded root-only (PCI passthrough `hostpci`, `args`, bind mounts) [PX2]. CLI `qm`/`pct` run as root count as `root@pam` [PX3], so `sudo qm set` covers those. pve2's `pbs2` storage uses `root@pam`'s password (`proxmox.md.j2:242-246`) and must move to a token first. Not clustered, so `pvecm add`'s root password prompt doesn't apply [PX4] | Physical console with root's password. Keep it as break glass, and add TOTP/WebAuthn to `root@pam` [PX5] |
| PBS (on pve2) | Follows pve2's root | `root@pam` "corresponds to the Unix superuser" [PB1]. Tokens can't exceed their user; `DatastoreBackup` can't prune [PB1] | pve2's console |
| pfSense | admin stays, but leaves day-to-day use | admin "cannot be deleted, and its username may not be changed" [PF1]. It can be disabled [PF2], but LDAP/RADIUS GUI auth falls back to the local DB anyway [PF3]. SSH can be "Public Key Only" [PF4] | Console option 3 resets admin's password [PF5]. The console is pve1's noVNC, so pve1 root recovers it |
| gaming (Windows) | Keep the admin password | `TrustedUserCAKeys` isn't on Microsoft's unsupported-options list [W1]. Principal mapping for local admins is UNVERIFIED | Proxmox console on pve2 |

**Dropping the deploy-time prompts:**

- Add the principal `admin` to the workstation's and pve1's certificates. Both pfSense
  (`src/nodes/router/sshd_extra:1`) and the gaming VM (`src/nodes/gaming/sshd_start.conf:3`)
  already set `TrustedUserCAKeys` globally, and both log in as `admin`.
- Then switch pfSense SSH to "Public Key Only" [PF4]. That removes the router password from
  `upload_src.sh:20-21` and `ssh_cert_gen.sh.j2:48`.
- It removes the gaming password from `upload_src.sh:27-28` too, if the Windows mapping works
  (test first).

### CA passphrases: replace with hardware keys?

| CA key | Hardware option | Verdict |
| --- | --- | --- |
| `ca_ssh_key` (user CA) | **FIDO `ed25519-sk` CA keys, one per YubiKey** | **Do it.** <ul><li>`ssh-keygen -s` signs with an sk key: it asks for touch per certificate, and for the PIN if `verify-required` is set [SS4]</li><li>sshd's default `CASignatureAlgorithms` includes `sk-ssh-ed25519@openssh.com`, on Debian 12 and current [SS5]</li><li>sk keys can't be backed up [SS3]. Instead, make one CA key on each of two YubiKeys and list both public keys in `ca_ssh_key.pub`; `TrustedUserCAKeys` takes one key per line [SS5]</li><li>Losing one YubiKey costs nothing; remove its line</li><li>Signing happens on pve1 with the YubiKey plugged in (Debian's openssh-client depends on libfido2 [D1]). Avoid agent-held CA signing on 10.1, fixed in 10.2 [SS6]; trixie's 10.0 is unaffected</li></ul> |
| `ca_ssh_host_key` (host CA, no passphrase today) | Same as the user CA: two sk keys, two `@cert-authority` lines | Optional. It signs ~10 host certs a year; the yearly run gains one touch per host |
| PIV alternative for SSH | `ssh-keygen -D libykcs11.so -s ca.pub` [SS7]. Ed25519 over PKCS#11 needs OpenSSH 10.1+ [SS8], and 10.1/10.2 had PKCS#11 PIN bugs [SS9]. So on trixie's 10.0 it must be ECDSA P-256/384 | Not chosen: FIDO is simpler and needs no import ceremony |
| Intermediate X.509 CA | Generate off-device, import into two YubiKeys over PIV (`ykman piv keys import`) [Y3]. Sign through `pkcs11-provider` (trixie 1.0 [D3]) with `openssl ca -keyfile "pkcs11:…"` [O2] [O3]. Imported keys get no attestation [Y4] | **Not now.** It means re-keying the intermediate and redistributing the chain. The current key is RSA-4096, which PIV supports only from firmware 5.7 [Y5]. The `openssl ca` + pkcs11-provider path is untested here. Keep the passphrase, move it into Vaultwarden, and fix the `-passin pass:` leak |
| Root X.509 CA | Same PIV path, or none | **Take it offline instead** (Q3) |

## 4. Q3: which secrets stay offline-only

| Secret | Why offline-only |
| --- | --- |
| **Root CA key `ca.key.pem` and its passphrase** | <ul><li>Used once a decade (`openssl.root.cnf.j2:34`), with no root CRL to refresh</li><li>NIST SP 800-57 Pt 1 Rev 5 §5.5.2: root compromise forces every relying party to install a new trust anchor, so "elaborate precautions … may be justified"; §9.5.4 ranks a root-signing key among the most expensive to recover [N1]</li><li>CA/B Forum's network security requirements put Root CA Systems on a separate, air-gapped network [N2]. smallstep: after signing the intermediate "You no longer need your root_ca.key" [N3]</li><li>Today the key sits on pve1 and in every PBS host backup (`pve1_recovery.md.j2:35`). Move it to the escrow sticks only. Keep the passphrase on paper, stored apart from the sticks; CA/B BR §6.2 calls for "physical security, encryption, or a combination" [N4]</li></ul> |
| **Escrow bundle passphrase** (`age -p`, 04 item 5) and the escrow age identity's passphrase | They protect the copy used when everything else is gone. They can't live in Vaultwarden, which is itself in the bundle |
| **Vaultwarden master password** | It decrypts the store; the store can't hold its own key. Memorize it, and keep a paper copy with the escrow passphrase, as 1Password's Emergency Kit model does [P4] |
| **The two SSH-CA YubiKeys** | Physical. One lives with pve1, one with the off-site escrow stick |
| **A copy of the recovery-before-secsvcs set** (pve1/pve2 root, pfSense admin, ACB key and password) | The pve1 rebuild needs them before Vaultwarden is back. They live in Vaultwarden *and* as a short `breakglass.txt` inside the escrow bundle. Losing the ACB password makes those backups unrecoverable [PF6] |

Everything else lives in Vaultwarden, and reaches the escrow only through the periodic export.

## 5. Recommendation

**Vaultwarden is the one store for human passwords. A short break-glass file and the rarely used
trust roots stay in the offline escrow bundle. Most passwords go away rather than move:**

- **No more sudo passwords.** manualadmin gets `NOPASSWD: ALL`, gated by a FIDO `ed25519-sk` login
  key with `verify-required` certificates. pve1's certificate loses `manualadmin`.
- **Root locked on every Debian node.** Break glass is the hypervisor console or `qm guest exec`.
- **Proxmox root stays:** a long random password plus TFA, in Vaultwarden and in `breakglass.txt`.
- **The SSH user CA moves to two FIDO keys,** so it has no passphrase.
- **The root X.509 CA leaves pve1** for the escrow sticks, with its passphrase on paper.

Rationale:

- Vaultwarden is already built, has the lowest friction, and 04 already escrows its export.
- Its one real weakness is the DR bootstrap. It is covered by keeping only the few
  recovery-before-secsvcs secrets in `breakglass.txt` inside the bundle.
- Removing the sudo, Debian root and SSH-CA passwords shrinks what has to be stored at all.
- Hosted managers buy availability that the escrow already provides, at the cost of the
  no-cloud goal. The agent-based PAM modules can't use the SSH CA.

## 6. Per-secret placement

| Secret | Store | Who / what can read it | How it's recovered |
| --- | --- | --- | --- |
| Root CA key + passphrase | Escrow sticks (key); paper, apart from the sticks (passphrase). **Removed from pve1 and PBS** | Maintainer with both | Both sticks lost: [Only the private CA is lost](../../docs/guides/pve1_recovery.md.j2) |
| Intermediate CA passphrase | Vaultwarden; escrow (export) | Maintainer; pve1 root while signing | Reset by re-keying the intermediate with the root |
| SSH user CA | Two YubiKeys (sk); handle files and `.pub` on pve1 | Whoever holds a YubiKey plus its PIN | One lost: drop its line. Both lost: the "Only the SSH CA is lost" path |
| SSH host CA | pve1 `/root/ssh` (as today); optionally two sk keys | pve1 root | as today |
| manualadmin password, all nodes | **None: locked** | — | Console / `qm guest exec` |
| Debian root password | **None: locked** | — | `SYSTEMD_SULOGIN_FORCE=1` / `init=/bin/bash` at the console |
| Debian and pfSense autoadmin passwords | **None: locked** (certificate-only login) | — | — |
| pve1, pve2 `root@pam` (PBS = pve2) | Vaultwarden; `breakglass.txt` in escrow; TFA on `root@pam` | Maintainer | Physical console. Lost: reset from a rescue boot |
| pve2 `pbs2` storage credential | A PBS token (`pve2@pbs!backup`) in `/etc/pve/priv/storage/`, replacing root's password | pve2 root | New token on pve2 |
| pfSense admin (web) | Vaultwarden; `breakglass.txt` | Maintainer | Console option 3 from pve1's noVNC |
| ACB device key + encryption password | Vaultwarden; `breakglass.txt` | Maintainer | Password lost: old ACB backups are gone [PF6]; PBS and escrow still hold `config.xml` |
| gaming admin | Vaultwarden | Maintainer | Proxmox console on pve2 |
| Linode account password + 2FA | Vaultwarden; `breakglass.txt` | Maintainer | Linode account recovery |
| Vaultwarden master password | Memory + paper with the escrow passphrase | Maintainer | None: that is the point |
| Vaultwarden admin token | Escrow (already planned, 04) | Maintainer | `vaultwarden hash` a new one |
| Escrow bundle passphrase, escrow age identity passphrase | Paper only | Maintainer | Re-cut the bundle from pve1 |

## 7. Follow-up tasks

1. **Debugging recipe:** replace `docs/debugging.md:802-810` with "sudo is passwordless for
   manualadmin, so `ssh manualadmin@HOST sudo …`" once task 4 lands. Until then the current
   `read -rs` recipe is correct; only the ticket's description of it is stale.
2. **Hardware login key:** add a step to `docs/guides/mac_personal.md.j2` and the `local` signing in
   `ssh_cert_gen.sh.j2:84-87`:
   - Homebrew openssh; `ssh-keygen -t ed25519-sk -O verify-required`.
   - Sign with `-O verify-required` and principals `manualadmin,autoadmin,admin`.
3. **Drop manualadmin from pve1's certificate:** `ssh_cert_gen.sh.j2:71` becomes `-n autoadmin,admin`.
   Add a dispatcher command `install_secrets` (`pve1_file_transfer: true`, stdin) and rewrite
   `secret_update.sh:25-37` to use it.
4. **NOPASSWD:** add `manualadmin ALL=(ALL) NOPASSWD: ALL` beside the dispatcher's sudoers. The
   router's sudoers is separate; pfSense admin is root already. Then:
   - lock the passwords on the Debian VMs and the manualadmin passwords on pve1/pve2;
   - drop the "root password" prompts from `upload_src.sh:45` and `secret_update.sh:27`;
   - update `CONTEXT.md` (manualadmin, "full sudo with password") and `docs/security.md:211-212`.
5. **Bootstrap fix** (independent of this ticket): document, or script in `ssh_cert_gen.sh`, the
   first-run install of `ca_ssh_key.pub` as manualadmin. Fix the stale "asks for the root
   password" notes in `docs/guides/pve1.md.j2:48-49` and `pve1_recovery.md.j2:343`.
6. **SSH user CA on two FIDO keys:**
   - Update `docs/guides/pve1.md.j2:34-37`: `ssh-keygen -t ed25519-sk -O application=ssh:homelab-ca`
     on each key.
   - `ca_ssh_key.pub` holds both lines.
   - `ssh_cert_gen.sh` signs with `-s` on the handle file of whichever key is plugged in.
   - Add the YubiKeys to 09's inventory.
7. **Root CA offline:**
   - Move `/root/ca/private/ca.key.pem` to the escrow sticks.
   - Exclude it from pve1's `backup.sh` stage.
   - Update `pve1_recovery.md.j2:35` ("Covered by": Escrow only) and the "Only the private CA is
     lost" section.
8. **`-passin` leak:** switch `self_signed_cert_gen.sh.j2` to `-passin fd:3` (or `env:`) [O1].
9. **pve2 PBS credential:** replace `--username root@pam --password ROOT_PASSWORD`
   (`proxmox.md.j2:242-246`) with a `pve2@pbs!backup` token holding `DatastoreBackup` on the
   `pve2` namespace. This fits backup-and-dr/11.
10. **TFA on `root@pam`** for pve1, pve2 and PBS; document it in `docs/guides/proxmox.md.j2`.
11. **pfSense:**
    - SSH "Public Key Only".
    - The `admin` principal (task 2/3) instead of the password prompts in `upload_src.sh:20-21` and
      `ssh_cert_gen.sh.j2:48`.
    - Test the same for gaming (`upload_src.sh:27-28`).
12. **backup-and-dr/04 escrow list:**
    - Add: the root CA key (*only* copy), `breakglass.txt` (pve1/pve2 root, pfSense admin, ACB
      device key + password, Linode account), and the Bitwarden export (already listed).
    - Note that the escrow age identity must be X25519, `age -p`-wrapped, not a passphrase
      recipient [A3].
    - List the paper items: escrow passphrase, identity passphrase, root CA passphrase, Vaultwarden
      master password.
    - Remove: the CA/SSH-CA passphrase hand-notes.
13. **backup-and-dr/09 TODOs and `pve1_recovery.md.j2`:**
    - Line 42: CA passphrases go to "Vaultwarden + escrow (intermediate); paper (root); replaced
      by YubiKeys (SSH CA)".
    - Line 61: ACB goes to "Vaultwarden + `breakglass.txt`".
    - Lines 267-268: "needs each host's sudo password" becomes "passwordless sudo".
    - Drop the `<host>_root_pswd` TODO in 09's comment; those keys are not to be added to SOPS.
14. **Stale comment:** `secret_update.sh:21` "SOPS doesn't support SSH keys" (SOPS ≥3.10 does
    [S1]). Optional: encrypt per-host files with SOPS directly.

## 8. Sources

Repo references are inline. External:

- [A1] age-plugin-yubikey README: <https://github.com/str4d/age-plugin-yubikey/blob/main/README.md>
- [A2] age README, multiple recipients and plugins:
  - <https://github.com/FiloSottile/age/blob/main/README.md>
  - <https://github.com/FiloSottile/age/blob/main/doc/age.1.ronn>
- [A3] age spec, scrypt stanza must be alone: <https://github.com/C2SP/C2SP/blob/main/age.md>
- [A4] age README, passphrase-encrypted identity files:
  - <https://github.com/FiloSottile/age/blob/main/README.md>
- [A5] age v1.3.0 release (`age1tag`): <https://github.com/FiloSottile/age/releases/tag/v1.3.0>
- [B1] Bitwarden, using Bitwarden offline: <https://bitwarden.com/help/using-bitwarden-offline/>
- [B2] Bitwarden, log in vs unlock: <https://bitwarden.com/help/understand-log-in-vs-unlock/>
- [B3] Bitwarden, vault timeout (lock keeps data, log out removes it):
  - <https://bitwarden.com/help/vault-timeout/>
- [B4] Bitwarden security whitepaper: <https://bitwarden.com/help/bitwarden-security-white-paper/>
- [B5] Bitwarden export and encrypted export:
  - <https://bitwarden.com/help/export-your-data/>
  - <https://bitwarden.com/help/encrypted-export/>
  - <https://bitwarden.com/help/cli/>
- [B6] Bitwarden emergency access: <https://bitwarden.com/help/emergency-access/>
- [B7] Bitwarden pricing: <https://bitwarden.com/pricing/>
- [B8] Bitwarden blog, offline access (2022):
  - <https://bitwarden.com/blog/configuring-bitwarden-clients-for-offline-access/>
- [D1] Debian openssh-server/-client (trixie 10.0p1, bookworm 9.2p1, libfido2 dependency):
  - <https://packages.debian.org/trixie/openssh-server>
  - <https://packages.debian.org/bookworm/openssh-server>
  - <https://packages.debian.org/trixie/openssh-client>
- [D2] Debian trixie age 1.2.1: <https://packages.debian.org/trixie/age>
- [D3] Debian trixie pkcs11-provider: <https://packages.debian.org/trixie/pkcs11-provider>
- [K1] KeePassXC docs, KDBX4 and Argon2:
  - <https://keepassxc.org/docs/KeePassXC_UserGuide#_database_settings>
- [K2] KeePassXC FAQ, YubiKey challenge-response: <https://keepassxc.org/docs/>
- [K3] KeePassXC user guide, creating a YubiKey backup:
  - <https://keepassxc.org/docs/KeePassXC_UserGuide#_creating_a_yubikey_backup>
- [K4] KeePassXC FIDO2 hmac-secret request: <https://github.com/keepassxreboot/keepassxc/issues/3560>
- [K5] keepassxc-cli man page:
  - <https://github.com/keepassxreboot/keepassxc/blob/develop/docs/man/keepassxc-cli.1.adoc>
- [L1] passwd(1), trixie: <https://manpages.debian.org/trixie/passwd/passwd.1.en.html>
- [L2] OpenSSH lock check only without PAM:
  - <https://github.com/openssh/openssh-portable/blob/master/auth.c>
- [L3] Debian sshd_config(5), README.Debian (UsePAM yes):
  - <https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html>
  - <https://sources.debian.org/src/openssh/trixie/debian/README.Debian/>
- [L4] systemd `SYSTEMD_SULOGIN_FORCE`:
  - <https://github.com/systemd/systemd/blob/main/docs/ENVIRONMENT.md>
- [L5] sulogin(8): <https://manpages.debian.org/trixie/util-linux/sulogin.8.en.html>
- [L6] Debian 13 installation guide, root password:
  - <https://www.debian.org/releases/trixie/amd64/ch06s03.en.html>
- [M1] Yubico, macOS bundled OpenSSH lacks libfido2:
  - <https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html>
- [M2] Homebrew openssh: <https://formulae.brew.sh/api/formula/openssh.json>
- [N1] NIST SP 800-57 Pt 1 Rev 5 (§5.5.2, §9.5.4, Table 7):
  - <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-57pt1r5.pdf>
- [N2] CA/B Forum Network and Certificate System Security Requirements §1.2.1, §2.2.4:
  - <https://github.com/cabforum/netsec/blob/main/docs/NSR.md>
- [N3] smallstep, cryptographic protection:
  - <https://smallstep.com/docs/step-ca/cryptographic-protection/>
  - <https://smallstep.com/blog/build-a-tiny-ca-with-raspberry-pi-yubikey/>
- [N4] CA/B Forum Baseline Requirements §6.1.7, §6.2:
  - <https://github.com/cabforum/servercert/blob/main/docs/BR.md>
- [O1] OpenSSL passphrase options: <https://docs.openssl.org/3.0/man1/openssl-passphrase-options/>
- [O2] openssl-ca(1), 3.0: <https://docs.openssl.org/3.0/man1/openssl-ca/>
- [O3] pkcs11-provider HOWTO:
  - <https://github.com/latchset/pkcs11-provider>
  - <https://raw.githubusercontent.com/latchset/pkcs11-provider/main/HOWTO.md>
- [P1] 1Password membership, offline: <https://support.1password.com/explore/membership/>
- [P2] 1Password, Unlock with SSO security: <https://support.1password.com/sso-security/>
- [P3] 1Password security design, Secret Key / 2SKD:
  - <https://agilebits.github.io/security-design/apsk.html>
- [P4] 1Password Emergency Kit: <https://support.1password.com/emergency-kit/>
- [P5] 1Password export (1PUX unencrypted): <https://support.1password.com/export/>
- [P6] 1Password pricing: <https://1password.com/pricing/password-manager>
- [PA1] Debian package search, pam-ssh-agent-auth:
  - <https://packages.debian.org/search?keywords=pam-ssh-agent-auth&searchon=names&suite=all&section=all>
- [PA2] Debian tracker, pam-ssh-agent-auth: <https://tracker.debian.org/pkg/pam-ssh-agent-auth>
- [PA3] Upstream commits and tags:
  - <https://api.github.com/repos/jbeverly/pam_ssh_agent_auth/commits?per_page=3>
  - <https://api.github.com/repos/jbeverly/pam_ssh_agent_auth/tags>
- [PA4] Cert support issue and PR:
  - <https://github.com/jbeverly/pam_ssh_agent_auth/issues/31>
  - <https://github.com/jbeverly/pam_ssh_agent_auth/pull/49>
- [PA5] sk keys and destination constraints:
  - <https://github.com/jbeverly/pam_ssh_agent_auth/issues/23>
  - <https://github.com/jbeverly/pam_ssh_agent_auth/issues/44>
- [PA6] pam_ssh_agent_auth(8), trixie:
  - <https://manpages.debian.org/trixie/libpam-ssh-agent-auth/pam_ssh_agent_auth.8.en.html>
- [PB1] PBS user management: <https://pbs.proxmox.com/docs/user-management.html>
- [PF1] pfSense users: <https://docs.netgate.com/pfsense/en/latest/usermanager/users.html>
- [PF2] pfSense user manager source (Disabled flag):
  - <https://github.com/pfsense/pfsense/blob/master/src/usr/local/www/system_usermanager.php>
- [PF3] pfSense authentication settings:
  - <https://docs.netgate.com/pfsense/en/latest/usermanager/settings.html>
- [PF4] pfSense advanced admin access (SSH key only):
  - <https://docs.netgate.com/pfsense/en/latest/config/advanced-admin.html>
- [PF5] pfSense console menu, locked out:
  - <https://docs.netgate.com/pfsense/en/latest/config/console-menu.html>
  - <https://docs.netgate.com/pfsense/en/latest/troubleshooting/locked-out.html>
- [PF6] pfSense ACB configuration and restore:
  - <https://docs.netgate.com/pfsense/en/latest/backup/acb-config.html>
  - <https://docs.netgate.com/pfsense/en/latest/backup/acb-restore.html>
- [PR1] Debian package search, rssh:
  - <https://packages.debian.org/search?keywords=rssh&searchon=names&suite=all&section=all>
- [PR2] pam_rssh releases: <https://api.github.com/repos/z4yx/pam_rssh/releases>
- [PR3] pam_rssh CA issue: <https://github.com/z4yx/pam_rssh/issues/29>
- [PR4] pam_rssh README: <https://github.com/z4yx/pam_rssh>
- [PX1] PVE PAM realm source:
  - <https://git.proxmox.com/?p=pve-access-control.git;a=blob_plain;f=src/PVE/Auth/PAM.pm;hb=HEAD>
- [PX2] qemu-server root-only checks:
  - <https://git.proxmox.com/?p=qemu-server.git;a=blob_plain;f=src/PVE/API2/Qemu.pm;hb=HEAD>
- [PX3] PVE CLI runs as root@pam:
  - <https://git.proxmox.com/?p=pve-common.git;a=blob_plain;f=src/PVE/RESTEnvironment.pm;hb=HEAD>
- [PX4] PVE admin guide (cluster join, node SSH):
  - <https://pve.proxmox.com/pve-docs/pve-admin-guide.html>
- [PX5] PVE user management (realms, root@pam, TFA):
  - <https://pve.proxmox.com/pve-docs/chapter-pveum.html>
- [S1] SOPS changelog (3.10.0: age plugins, SSH, passphrase identities, `SOPS_AGE_KEY_CMD`):
  - <https://github.com/getsops/sops/blob/main/CHANGELOG.md>
- [S2] SOPS age keysource:
  - <https://github.com/getsops/sops/blob/main/age/keysource.go>
  - <https://getsops.io/docs/usage/identities/age/>
- [SS1] ssh(1), agent forwarding warning:
  - <https://manpages.debian.org/trixie/openssh-client/ssh.1.en.html>
- [SS2] ssh-keygen(1), `verify-required`; OpenSSH 8.4/9.1 notes:
  - <https://man.openbsd.org/ssh-keygen.1>
  - <https://www.openssh.org/txt/release-8.4>
  - <https://www.openssh.org/txt/release-9.1>
- [SS3] ssh-keygen(1), FIDO keys can't be exported: <https://man.openbsd.org/ssh-keygen.1>
- [SS4] ssh-keygen.c `do_ca_sign` (PIN and touch for sk CA keys):
  - <https://raw.githubusercontent.com/openssh/openssh-portable/master/ssh-keygen.c>
- [SS5] sshd_config(5), `CASignatureAlgorithms`, `TrustedUserCAKeys`:
  - <https://man.openbsd.org/sshd_config.5>
  - <https://manpages.debian.org/bookworm/openssh-server/sshd_config.5.en.html>
- [SS6] OpenSSH 10.2 release notes (agent CA signing fix): <https://www.openssh.org/txt/release-10.2>
- [SS7] Yubico, PIV for SSH through PKCS#11:
  - <https://developers.yubico.com/PIV/Guides/SSH_with_PIV_and_PKCS11.html>
- [SS8] OpenSSH 10.1 release notes (Ed25519 PKCS#11): <https://www.openssh.org/txt/release-10.1>
- [SS9] OpenSSH 10.3 release notes (PKCS#11 PIN fix): <https://www.openssh.org/txt/release-10.3>
- [SU1] sudoers(5): <https://www.sudo.ws/docs/man/sudoers.man/>
- [V1] Vaultwarden README, .env.template, 1.37.4:
  - <https://github.com/dani-garcia/vaultwarden/blob/main/README.md>
  - <https://github.com/dani-garcia/vaultwarden/blob/main/.env.template>
- [V2] Vaultwarden wiki, backing up your vault:
  - <https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault>
- [W1] Microsoft, OpenSSH server configuration:
  - <https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration>
- [Y1] Yubico, ykman OTP chalresp; challenge-response secrets not extractable:
  - <https://docs.yubico.com/software/yubikey/tools/ykman/OTP_Commands.html>
  - <https://docs.yubico.com/yesdk/users-manual/application-otp/challenge-response.html>
- [Y2] Yubico, FIDO2 SSH (ed25519-sk needs 5.2.3+):
  - <https://developers.yubico.com/SSH/Securing_SSH_with_FIDO2.html>
- [Y3] ykman PIV commands: <https://docs.yubico.com/software/yubikey/tools/ykman/PIV_Commands.html>
- [Y4] Yubico, PIV attestation (none for imported keys):
  - <https://docs.yubico.com/yesdk/users-manual/application-piv/attestation.html>
- [Y5] YubiKey firmware 5.7 (RSA-3072/4096, Ed25519 in PIV):
  - <https://docs.yubico.com/hardware/yubikey/yk-tech-manual/yk5-firmware-5.7.html>
