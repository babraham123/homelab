# Configure GPUs on Linux

## Intel iGPU

- Install drivers
```bash
sudo su
# driver and tools
apt install -y intel-gpu-tools vainfo intel-media-va-driver
# Their version of CUDA
apt install intel-opencl-icd
reboot
```
- Verify after PCI passthrough
```bash
ls /dev/dri | grep render
sudo lspci -nnv | grep VGA
vainfo
```

## Nvidia GPU

- Find the right [Nvidia version](https://www.nvidia.com/en-in/drivers/)
- Find the right [CUDA version](https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Debian&target_version=12)
- Install drivers, [ref](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/index.html#debian-installation)
```bash
# prep
apt update
apt upgrade
apt install -y linux-headers-$(uname -r)
add-apt-repository contrib

# network repo
# Use debian12 if legacy 580 drivers are not available
distro="debian13"
arch="x86_64"
wget https://developer.download.nvidia.com/compute/cuda/repos/$distro/$arch/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt update

# Pin the nvidia driver version
apt install nvidia-driver-pinning-580

# install toolkit and drivers
apt install -y cuda-drivers nvtop
reboot
```
- Verify after PCI passthrough
```bash
ls /dev/nvidia*
sudo systemctl status nvidia-persistenced
cat /proc/driver/nvidia/version
sudo lspci -nnv | grep -i nvidia
nvidia-smi
nvtop
```

## Coral TPU

- Install the driver and TPU runtime, [ref](https://coral.ai/docs/m2/get-started/#2-install-the-pcie-driver-and-edge-tpu-runtime)
```bash
# Confirm apex driver is not already installed
lsmod | grep apex

echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
apt update

apt install -y gasket-dkms libedgetpu1-std
reboot
```
- Verify after PCI passthrough
```bash
lspci -nn | grep 089a
ls /dev/apex_0
```
