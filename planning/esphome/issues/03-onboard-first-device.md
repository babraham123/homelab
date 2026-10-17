# 03. Onboard the first device: browser flash, fixed name, HA

Status: ready-for-human
Type: task
Repo: homelab
Source: maintainer request 2026-10-13; design in [spec.md](../spec.md)
Blocked by: 02

Proves the whole loop on one real board by following
[docs/guides/esphome.md.j2](../../../docs/guides/esphome.md.j2), and corrects the guide where it's
wrong.

## Steps

1. pfSense: confirm homesvcs reaches WiFiIoT. From homesvcs,
   `ping <an IoT device>` and `nc -zv <it> 6053` against anything already on the VLAN. If not, add
   a LAN rule from homesvcs to the WiFiIoT net on TCP 6053, 3232, 8266, 2040 and ICMP.
2. pfSense, WiFiIoT DHCP server:
   - shrink the pool to .100–254;
   - set the domain name to `iot.home.arpa`;
   - in DNS Resolver, tick "Register DHCP static mappings";
   - update `router.md.j2`'s VLAN step to match.

   Existing IoT devices with a lease in .10–99 move on renewal. Before shrinking, check whether HA
   reaches any of them by IP.
3. Onboard one board with the guide.
4. From homesvcs: `dig +short <name>.iot.home.arpa` returns its .10–99 address, not websvcs. If the
   name registered under the system domain instead, record which one, and fix the guide and
   `common/base.yaml`.
5. Change something trivial, then Install → Wirelessly. The OTA must go through by name.
6. Restore drill: run `backup`, then check that the staged `volumes/esphomeconfig` has the device's
   YAML.

## Record under ## Answer

- Board, USB chip, and whether BOOT was needed.
- Whether Web Serial worked through Traefik and Authelia with no extra settings.
- Whether the pfSense rule was needed.
- Where the name registered.

Fix whatever in `docs/guides/esphome.md.j2` didn't match, then resolve.

## Comments
