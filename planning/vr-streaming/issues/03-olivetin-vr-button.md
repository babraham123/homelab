# 03. OliveTin "Start VR" button

Status: needs-info Type: task Repo: homelab Source: maintainer request 2026-10-12; research in
[automation-research.md](../automation-research.md#shape-for-03) Blocked by: 02

## Change

In the Gaming fieldset of `src/services/olive_tin/config.yaml.j2`:
- rename "Start Gaming Server" to "Start Gaming (TV)";
- add "Start Gaming (VR)":
  `ssh autoadmin@router start_pve2 && ssh autoadmin@pve2 start_gaming_vm && ssh autoadmin@gaming
  StartVR`, with the same `acls`, `timeout` and `maxConcurrent` as the TV button.

The two buttons differ only in the last trigger. Render them from a Jinja loop over
`[('TV', 'StartSunshine'), ('VR', 'StartVR')]` so the start chain exists once, as the template's
"All Commands" loop already does. UEVR mode adds one tuple to that loop in 06. The ids become
`main_start_gaming_tv` / `main_start_gaming_vr`; nothing else refers to `main_start_gaming`.
"Stop Gaming Server" is unchanged. Check the whitespace in the rendered output.

Pressing a start button while the VM is already up switches modes: `start_gaming_vm` returns at
once when the VM answers ping. The button finishes when the trigger file is dropped, not when Link
is up, as the TV button does today.

Optional: put the start and stop buttons in one `actionGroups` entry with `maxConcurrent: 1`
(OliveTin 3000.20.0+), so a second press queues instead of overlapping.

## Acceptance

- From a phone on WiFiTrusted, "Start Gaming (VR)" with pve2 off ends with the headset able to
  connect over Air Link.
- "Start Gaming (TV)" from VR mode switches to Sunshine.

## Comments
