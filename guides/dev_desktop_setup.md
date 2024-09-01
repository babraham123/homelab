# Development desktop setup
Guide to create the devtop VM. It's intended as an environment for general software development and the execution of AI models.
TODO: Add vscode, language scripts, remote desktop, model management

- First setup Linux using [debian_setup.md](./debian_setup.md)

## Install GPU firmware
- Disable secure boot, [vid](https://www.youtube.com/watch?v=js_Xoa0f8zM)

- Install CUDA, [ref](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#debian)
```bash
sudo su
apt install -y linux-headers-$(uname -r) build-essential python3-pip

# https://developer.nvidia.com/cuda-downloads
# Base installer
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
add-apt-repository contrib
apt-key del 7fa2af80
apt update
apt install -y cuda-toolkit-12-4
# Driver installer
apt install -y cuda-drivers firmware-misc-nonfree
reboot
```

- Post-install steps
```bash
echo 'export PATH=/usr/local/cuda-12.4/bin${PATH:+:${PATH}}' >> ~/.zshrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.zshrc
source ~/.zshrc
sudo apt install -y nvtop g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev
```

- Confirm GPU status
```bash
ls /dev/nvidia*
sudo systemctl status nvidia-persistenced
cat /proc/driver/nvidia/version
sudo lspci -nnv | grep VGA
nvidia-smi
nvtop
```
