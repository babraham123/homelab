# Development desktop setup
Guide to create the devtop VM. It's intended as an environment for general software development and the execution of AI models.
TODO: Add vscode, language scripts, remote desktop, model management

- First setup [Debian Linux](./debian.md)

## Improve the terminal emulator
- Log on via the Proxmox VNC console
- Enable the Solarized Dark color theme, [src](https://github.com/aruhier/gnome-terminal-colors-solarized)
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

## Support remote VNC
- Enable copy paste
```bash
sudo apt -y install spice-vdagent
ssh {{ username }}@pve2.{{ site.url }}
```
- Update VM config
```bash
sudo su
vmid=`/usr/local/bin/get_vm_id.sh devtop`
qm set $vmid -vga std,clipboard=vnc
echo "args: -vnc 0.0.0.0:{{ devtop.ip.split('.')[-1] }}" >> /etc/pve/local/qemu-server/$vmid.conf
exit
exit
sudo reboot
```
TODO: add a password, [ref](https://forum.proxmox.com/threads/setting-vnc-password-permanently.46655/#post-221726), [ref2](https://pve.proxmox.com/wiki/VNC_Client_Access)
- add a pve2 secrets file, 
