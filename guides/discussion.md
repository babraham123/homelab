# Discussion
High level questions that shaped the homelab's requirements and design.

1. Why self host?
1. Why prefer open source software?
1. Why tunnel into home network?
  For all of the same reasons people use a VPN (better security and privacy). Tailscale offers a similar feature called Tailscale Funnel. I can also connect my personal device to the overlay network if I want direct access to the local network. I prefer to 
1. Why run containers as Systemd services?
  Systemd greatly simplifies the management of containers. It has a bunch of builtin levers to handle failures, logging, restarts, isolation, etc. Also Quadlet offers a way to autoupdate your containers.
