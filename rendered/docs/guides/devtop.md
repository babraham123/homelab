# Development desktop setup

The devtop VM, for software development and running AI models.
TODO: Add vscode, language scripts, remote desktop, model management

- First setup [Debian Linux](./debian.md)

## Improve the terminal emulator

- Log on via the Proxmox VNC console
- Enable the Solarized Dark color theme,
  [src](https://github.com/aruhier/gnome-terminal-colors-solarized)

```bash
# Confirm that you're using gnome
echo $XDG_CURRENT_DESKTOP
sudo apt -y install dconf-cli
git clone https://github.com/aruhier/gnome-terminal-colors-solarized.git
cd gnome-terminal-colors-solarized
./install.sh
echo 'eval `dircolors ~/.dir_colors/dircolors`' >> ~/.zshrc
source ~/.zshrc
```

## Passthrough the GPU

- Disable secure boot, [vid](https://www.youtube.com/watch?v=js_Xoa0f8zM)

- Install Nvidia drivers using the [GPU guide](./gpu.md)

- Passthrough the GPU, using the [Proxmox guide](./proxmox.md)

- Additional tools

```bash
echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' >> ~/.zshrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.zshrc
source ~/.zshrc
sudo apt install -y build-essential python3-pip g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev
```

- Export GPU metrics, scraped by websvcs' vmagent

```bash
sudo su
cd /root/homelab-rendered
src/base/debian/install_svcs.sh nvidia_gpu_exporter
ufw allow in from 192.168.2.20 to any port 9835 proto tcp
exit
```

## Support remote VNC

- Enable copy paste

```bash
sudo apt -y install spice-vdagent
ssh manualadmin@pve2
```

- Update VM config

```bash
sudo su
vmid=`/root/homelab-rendered/src/nodes/pve2/get_vm_id.sh devtop`
qm set $vmid -vga std,clipboard=vnc
qm set $vmid --args '-vnc 127.0.0.1:22,password=on'
exit
exit
sudo reboot
```

- Connect from the laptop through an SSH tunnel. The display listens only on pve2's loopback, so
  the tunnel's SSH login is the authentication. The VNC password, `devtop.vnc_password` in
  `vars.yml`, is only there because macOS Screen Sharing hangs on a display without one; pve2's
  hookscript sets it at every start, after `install_hookscript`.

```bash
# On the laptop: opens the tunnel and the VNC viewer, Ctrl+C closes the tunnel
tools/devtop_vnc.sh
# By hand: leave it running
ssh -N -L 5922:127.0.0.1:5922 manualadmin@pve2
# VNC client → localhost:5922
```
