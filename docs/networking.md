# Networking

How traffic moves: physical topology, VLANs, DNS, and the three-tier ingress chain. All addresses
below are the placeholder values from `vars.template.yml`.

The ground-truth configs are `src/services/dns/unbound.conf.j2`,
`src/services/haproxy/haproxy.cfg.j2`, the per-node `src/nodes/<node>/traefik/` directories, and
[the router guide](guides/router.md).

## Physical and logical topology

pfSense runs as a VM on pve1 with all four of the mini PC's 2.5 GbE NICs (Intel i226, `igc0`–`igc3`,
in PCI address order) PCI-passed through to it. The Proxmox host itself has no physical uplink: it
sits on the virtual bridge `vmbr0`, with the pfSense VM as its gateway.

| pfSense interface | Physical port | Network | Subnet |
| ------------------- | --------------- | --------- | -------- |
| WAN | igc0 | ISP uplink | (DHCP from ISP) |
| LAN | igc1 | WiFi AP trunk (VLAN parent) | 192.168.1.0/24 |
| pve2 | igc2 | pve2 uplink | 192.168.2.0/24 |
| LAN2 | igc3 | Wired devices | 192.168.3.0/24 |
| OPT (vmbr0) | virtual | pve1 + its VMs | 192.168.4.0/24 |

```mermaid
flowchart TB
    isp(("ISP"))

    subgraph pve1host["pve1 (mini PC)<br/>192.168.4.10"]
        pfsense["pfSense VM<br/>gateway .1 on every subnet"]
        vmbr0["vmbr0 virtual bridge<br/>192.168.4.0/24"]
        secsvcs["secsvcs<br/>192.168.4.20<br/>containers 10.10.0.0/24"]
        homesvcs["homesvcs<br/>192.168.4.21<br/>containers 10.12.0.0/24"]
    end

    subgraph pve2host["pve2 (tower)<br/>192.168.2.0/24"]
        pve2["pve2 host<br/>192.168.2.10"]
        websvcs["websvcs<br/>192.168.2.20<br/>containers 10.11.0.0/24"]
        gaming["gaming<br/>192.168.2.21"]
        devtop["devtop<br/>192.168.2.22"]
    end

    ap["EAP660 HD AP<br/>tagged VLANs 10 / 11 / 12"]
    wired["Wired devices<br/>192.168.3.0/24"]

    isp -- "igc0 WAN" --> pfsense
    pfsense -- "igc1 LAN trunk" --> ap
    pfsense -- "igc2" --> pve2host
    pfsense -- "igc3 LAN2" --> wired
    pfsense -. "OPT, no physical port" .- vmbr0
    vmbr0 -. "vNIC" .- secsvcs
    vmbr0 -. "vNIC" .- homesvcs

    style pve1host stroke:#a78bfa,stroke-width:2px,fill:transparent
    style pve2host stroke:#a78bfa,stroke-width:2px,fill:transparent
    classDef ext stroke:#38bdf8,fill:transparent
    classDef gate stroke:#f87171,fill:transparent
    classDef host stroke:#a78bfa,fill:transparent
    classDef dev stroke:#4ade80,fill:transparent
    class isp ext
    class pfsense gate
    class vmbr0,secsvcs,homesvcs,pve2,websvcs,gaming,devtop host
    class ap,wired dev
```

Each VM gets a static IP in its host's subnet from a pfSense DHCP static mapping, and each container
VM runs its own Podman bridge network for containers (`net.network` quadlet):

| Node | VM IP | Container subnet |
| ------ | ------- | ------------------ |
| secsvcs | 192.168.4.20 | 10.10.0.0/24 |
| websvcs | 192.168.2.20 | 10.11.0.0/24 |
| homesvcs | 192.168.4.21 | 10.12.0.0/24 |
| vpnsvcs | public | 10.13.0.0/24 (telemetry, geoip_generator) |

Containers have static IPs within their subnet (see [Services](services.md)); the render pipeline
rejects duplicate container IPs at build time.

## VLANs

VLANs exist on the WiFi trunk today; wired VLANs are defined but waiting on a managed switch. Each
VLAN is its own pfSense interface and /24, with the VLAN ID as the third octet, and its own DHCP
scope.

| VLAN | Name | Subnet | SSID | Status |
| ------ | ------ | -------- | ------ | -------- |
| 10 | WiFiTrusted | 192.168.10.0/24 | cool-house / cool-house5 | active |
| 11 | WiFiIoT | 192.168.11.0/24 | machines (2.4 GHz) | active |
| 12 | WiFiGuest | 192.168.12.0/24 | welcome (5 GHz) | active |
| 20 | WiredTrusted | 192.168.20.0/24 | n/a | planned (needs managed switch) |
| 21 | WiredIoT | 192.168.21.0/24 | n/a | planned |

The intent is three-tier segmentation: trusted devices, poorly-secured IoT devices, and
internet-only guests. IoT → trusted traffic is blocked by default with specific allowlisted services
(Home Assistant, MQTT); the guest VLAN routes only to the internet. The AP's management interface
lives on the trusted VLAN.

## DNS

Unbound on pfSense serves split-horizon DNS for the site domain:

- Every host and VM gets a `local-zone` redirect (e.g. `secsvcs.janedoe.com`).
- Per-service records are generated at render time from the `subdomain` of each service in
  `src/nodes/<node>/inventory.yml` (checked against the node's Traefik `Host()` rules), and the
  template loops emit records pointing at that node's VM IP (e.g.
  `auth.janedoe.com → 192.168.4.20`). HAProxy's SNI routing uses the same lists.
- A catch-all `janedoe.com A <websvcs>` record makes websvcs the default for the apex and anything
  unlisted.
- Internal-only names exist for `pgdb.` (Postgres) and `mqtt.` (Mosquitto); these resolve nowhere on
  the public internet.
- `vpn.janedoe.com` and `vpnsvcs.janedoe.com` are `transparent`: they resolve via public DNS to the
  VPS, even for internal clients.

Public DNS (at the registrar) points the domain and its subdomains at the VPS's public IP
(12.34.56.78). So the same URL works everywhere: outside the house you traverse HAProxy; inside,
Unbound short-circuits you straight to the VM.

DHCP hands clients the router as primary DNS with 1.1.1.1 as fallback, plus the site domain as a
search domain.

## mDNS across VLANs

Multicast DNS (device discovery for HomeKit, Chromecast, ESPHome, etc.) does not cross router
boundaries, which VLAN segmentation otherwise breaks. Three pieces bridge it:

- The pfSense **mDNS-Bridge package** repeats mDNS between VLANs, trusted VLANs only; the guest VLAN
  deliberately gets no discovery.
- A host-level **`mdns_repeater`** service on the container VMs repeats mDNS between the VM's NIC
  and its internal Podman bridge, so containers (e.g. Home Assistant) can discover devices.
- A firewall rule allows UDP/5353 to the multicast range across the bridged VLANs.

Gotcha: `avahi-daemon` must be disabled where `mdns_repeater` runs; it silently intercepts queries
first. `probes/mdns.js` is a probe script for verifying which service types are visible from a given
VLAN.

## Ingress: the three-tier chain

External requests cross three layers, each with a distinct job:

1. **HAProxy on vpnsvcs** is the only public listener (:80, :443). It runs in TCP mode for HTTPS: it
   inspects the TLS ClientHello's SNI and routes to a backend VM *without terminating TLS*. Rate
   limiting, geo-blocking, and attack-path filtering happen here (see
   [Security](security.md#the-edge-haproxy)).
2. **Tailscale mesh.** HAProxy's backends are the VMs' LAN IPs, reached over the tailnet through
   pfSense's advertised subnet route. The VPS funnels public traffic into the private network over
   WireGuard, filling a DMZ-like role. Headscale (self-hosted, on the same VPS) coordinates the
   mesh; its embedded DERP relay handles peers that can't connect directly.
3. **Traefik on each VM** terminates TLS (Let's Encrypt certs), enforces Authelia ForwardAuth, and
   routes by hostname to the local container. HAProxy speaks PROXY protocol v2 to Traefik so the
   real client IP survives the hops.

```mermaid
sequenceDiagram
    autonumber
    participant C as External client
    participant H as HAProxy on vpnsvcs
    participant T as Traefik on homesvcs
    participant A as Authelia on secsvcs
    participant S as Home Assistant (10.12.0.11)

    C->>+H: TLS ClientHello, SNI home.janedoe.com
    Note over H: 5s inspect-delay, stick-table rate limits,<br/>GeoIP check, SNI ACL match (no TLS termination)
    H->>+T: TCP passthrough + PROXY protocol v2, via Tailscale tunnel
    Note over T: TLS terminated here (Let's Encrypt cert)
    T->>+A: ForwardAuth: is this session valid?
    A-->>-T: 200 OK (else 302 to auth portal)
    T->>+S: HTTP to container 10.12.0.11
    S-->>-T: response
    T-->>-H: response (TLS)
    H-->>-C: response
```

Plain HTTP (:80) is handled in HTTP mode: HAProxy filters attack paths, then passes traffic through
so Traefik can answer ACME HTTP-01 challenges and redirect the rest to HTTPS.

Internal clients never touch tiers 1–2: Unbound resolves the service name straight to the VM, where
Traefik does the same TLS + ForwardAuth work.

### The client IP

CrowdSec's bans (it reads Traefik's and Authelia's logs), app rate limits and the access logs all
key on the client IP, so each hop passes it on and trusts it only from the hop before:

| Hop | Carries the client IP as | Trusted from |
| --- | --- | --- |
| HAProxy → Traefik | PROXY protocol v2 (`send-proxy-v2` on every node backend) | Traefik `proxyProtocol.trustedIPs` |
| Traefik entrypoint | `X-Forwarded-*` sent by the client; from any other source Traefik drops them | Traefik `forwardedHeaders.trustedIPs` |
| Traefik → app | `X-Forwarded-For` and `X-Real-Ip`, with the client IP Traefik resolved | the app's trusted-proxy setting |
| Traefik → Authelia (ForwardAuth, `trustForwardHeader`) | `X-Forwarded-For` | any peer that reaches :9091 |

Both Traefik `trustedIPs` lists hold only vpnsvcs's tailnet address (`vpnsvcs.tailnet_ip`).
pfSense routes tailnet traffic in the kernel without SNAT, so HAProxy's connections
keep that source address and every other tailnet, LAN or VLAN client arrives from its own address,
which can't assert a client IP. If pfSense falls back to SNAT (for example after a Tailscale package
update overwrites the System Patches change), HAProxy's connections arrive from the subnet gateway
`.1`, which isn't trusted: Traefik ignores the PROXY header and logs every public client as `.1`.

Per app:

- **Authelia** has no trusted-proxy setting: it takes the first `X-Forwarded-For` entry from any
  peer. The boundary is who can reach :9091: Traefik on secsvcs over the podman network, and the
  websvcs and homesvcs VMs (secsvcs `ufw`). Authelia's mTLS client certificates (off for now) would
  narrow it to the three Traefiks.
- **Vaultwarden**: `IP_HEADER=X-Forwarded-For`, `IP_HEADER_TRUSTED_PROXIES` = Traefik's container
  IP (`.6`). It takes the rightmost untrusted entry, so a forged leading entry is ignored.
- **copyparty**: `xff-src` = Traefik's container IP (`.6`), `rproxy: -1`: the rightmost entry,
  the one Traefik appended.

From the LAN there is no HAProxy hop: Traefik sees the client's own address.

## Outbound NAT

Outbound NAT is Hybrid: automatic rules plus one manual rule that gives UDP from the Tailscale
subnets (pve1, pve2, the trusted VLANs) an endpoint-independent mapping, a "Port Restricted Cone"
NAT. Each client keeps one external port across all destinations, so Tailscale peers hole-punch
directly instead of falling back to DERP. Everything else gets the default symmetric NAT. UPnP and
NAT-PMP are off, and no rule uses static port except pfSense's automatic one for IPsec (ISAKMP).
See [the router guide](guides/router.md).

## Throughput monitoring

`net_probe` on secsvcs measures the paths the homelab depends on, as the only client: an hourly
ping to websvcs and to the VPS, an Ookla speed test four times a day, and iperf3 to websvcs
(pve1 → pfSense → pve2) four times a day and to the VPS over Tailscale once a day, the VPS's
egress being billed. Heavy tests skip while their path is busy. The iperf3 servers (`:5201`) admit
only secsvcs: ufw on both, plus a Headscale ACL rule for the VPS, which sees secsvcs's LAN
address since pfSense routes subnet traffic without SNAT. "Network" dashboard;
[Services](services.md#observability) for the alerts.

## Router extras

pfSense also runs CoDel traffic shaping (bufferbloat control), ntopng for traffic inspection,
Telegraf for metrics export to VictoriaMetrics, and the Auto Config Backup package. Remote pfSense
actions (e.g. waking pve2) go through autoadmin; see [the router guide](guides/router.md).
