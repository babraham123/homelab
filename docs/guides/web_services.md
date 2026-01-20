# Web Services setup
Guide to setup websvcs on PVE2. Just service installation.

- Setup [Podman](./podman.md)

## Setup containers
- Install and start services
```bash
- Install and start containers
```bash
sudo su
cd /root/homelab-rendered
src/websvcs/install_svcs.sh traefik
src/websvcs/install_svcs.sh vmagent
src/websvcs/install_svcs.sh nginx
src/websvcs/install_svcs.sh homepage
src/websvcs/install_svcs.sh isso

# src/websvcs/install_svcs.sh go2rtc
# src/websvcs/install_svcs.sh piper
# src/websvcs/install_svcs.sh whisper
# src/websvcs/install_svcs.sh openwakeword

# src/websvcs/install_svcs.sh finance_exporter
src/websvcs/install_svcs.sh fluentbit

systemctl restart node_exporter
systemctl restart mdns_repeater
systemctl list-units | grep Homelab
```

## Setup homepage widgets

- Create an API token in the PVE console (for pve1, pve2 and pbs2)
  - Go to Datacenter >> Permissions >> API Tokens >> Add
  - user = api_ro@pam, token ID = homepage
  - Record the secret
```bash
ssh manualadmin@pve1.{{ site.url }}
sudo /root/homelab-rendered/src/pve1/secret_update.sh websvcs
```
  - Go to Permissions >> Add >> API Token Permission
  - path = /, token = api_ro@..., role = PVEAuditor, propagate = check
  - For PBS, Permissions -> Access Control, PVEAuditor -> Audit

## Hardware acceleration
This assumes there's a dedicated Nvidia GPU of some kind (Whisper and other models), an Intel iGPU (video transcoding) and a Coral TPU (Frigate object detection).

- Disable secure boot, [vid](https://www.youtube.com/watch?v=js_Xoa0f8zM)

- Passthrough the GPU, iGPU and TPU using the [Proxmox guide](./proxmox.md)

- Install Nvidia, Intel and Coral drivers using the [GPU guide](./gpu.md)

- Install the Nvidia container toolkit and CDI, [ref](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
```bash
sudo su
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update
apt install -y nvidia-container-toolkit nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1

# Generate the CDI spec
nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
# Check the names of the generated devices
nvidia-ctk cdi list
```
