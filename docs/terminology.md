# Terminology
The documentation sometimes use multiple words to refer to the same thing, or cryptic acronyms. Hopefully this glossary helps.

1. Cloud VM / cloudvpn / vpn
  The Linode cloud VM that funnels public traffic into my private network.
1. VM Host
  The base OS that's running Proxmox. It will host several VMs and should be very secure.
1. Secure Host / SBC / PVE1
  The singe board computer that runs the router software, critical web apps and Home Assistant. The base OS manages container secrets, self signed certificates and general provisioning, so it should be the most secure host in the system.
1. Web Host / PC Tower / PVE2
  The custom desktop computer that runs the rest of the web apps and various GUI based OSes. These web apps are generally user facing and may contain personal information.
1. Critical web apps
  These services are used to manage user security and monitor the overall system. As such they need to run 24/7.
