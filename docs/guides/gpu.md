# Configure GPUs on Linux

## Intel iGPU

- In the VM hardware settings, set the Display to none and add the PCI device. Reboot
- Install drivers
```bash
sudo su
# driver and tools
apt install -y intel-gpu-tools vainfo intel-media-va-driver
# Their version of CUDA
apt install intel-opencl-icd
# Or install manually if unavailable: https://github.com/intel/compute-runtime/releases
reboot
```
- Verify after PCI passthrough
```bash
ls /dev/dri | grep render
sudo lspci -nnv | grep VGA
vainfo
```

## Nvidia GPU

- In the VM hardware settings, add the PCI device and reboot
- Find the right [Nvidia version](https://www.nvidia.com/en-in/drivers/)
- Find the right [CUDA version](https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Debian&target_version=12)
  - Drivers: Currently 580 for the 3060Ti and Tesla P4
- Install drivers, [ref](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/index.html#debian-installation)
```bash
sudo su
# prep
apt update
apt upgrade
apt install -y linux-headers-$(uname -r)

# network repo
# Use debian12 if the legacy drivers are not available
version="580"
distro="debian13"
arch="x86_64"
wget https://developer.download.nvidia.com/compute/cuda/repos/$distro/$arch/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt update

# Pin the nvidia driver version
apt install nvidia-driver-pinning-$version

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

- In the VM hardware settings, add the PCI device and reboot
- Install the driver and TPU runtime, [ref](https://coral.ai/docs/m2/get-started/#2-install-the-pcie-driver-and-edge-tpu-runtime)
```bash
sudo su
# Confirm apex driver is not already installed
lsmod | grep apex

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | tee /etc/apt/keyrings/google-cloud.gpg
echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list
apt update
apt install -y gasket-dkms libedgetpu1-std
reboot
```
- If gasket fails to install
```bash
# Check for missing kernel support
vim /var/lib/dkms/gasket/1.0/build/make.log
apt purge gasket-dkms

# Build dependency from src (pkged version too old)
apt install -y build-essential pkg-config libelf-dev zlib1g-dev
version=1.5.0
wget "https://github.com/libbpf/libbpf/archive/refs/tags/v${version}.tar.gz" -O - | tar xz
cd "libbpf-${version}/src"
make
make install
make install PREFIX=/usr LIBDIR=/lib/x86_64-linux-gnu
cd ../..
ldconfig
apt install -y dwarves
# verify install worked
pahole --version

# Build from src
apt install -q -y --no-install-recommends git curl devscripts dkms dh-dkms build-essential debhelper
git clone https://github.com/feranick/gasket-driver
cd gasket-driver
debuild -us -uc -tc -b
cd ..
chmod 644 ./gasket-dkms_*_all.deb
apt install ./gasket-dkms_*_all.deb

reboot
```
- Verify after PCI passthrough
```bash
lspci -nn | grep 089a
ls /dev/apex_0
```
