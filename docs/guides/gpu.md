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
- Find the right [CUDA
  version](https://developer.nvidia.com/cuda-downloads?target_os=Linux&target_arch=x86_64&Distribution=Debian&target_version=12)
  - Drivers: Currently 580 for the 3060Ti and Tesla P4
- Install drivers,
  [ref](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/index.html#debian-installation)

```bash
sudo su
# Add debian12 as a second argument if the legacy drivers are not available
/root/homelab-rendered/src/base/debian/install_nvidia.sh 580
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

- Remove an old driver version

```bash
apt purge 'nvidia-*'
apt purge 'libnvidia-*'
apt autoremove --purge
```

## Coral TPU

- In the VM hardware settings, add the PCI device and reboot
- Build and install the driver,
  [ref](https://coral.ai/docs/m2/get-started/#2-install-the-pcie-driver-and-edge-tpu-runtime).
  The Edge TPU runtime comes with the container image that uses the TPU

```bash
sudo su
/root/homelab-rendered/src/base/debian/install_coral.sh
# If dkms fails on a new kernel
vim /var/lib/dkms/gasket/1.0/build/make.log
reboot
```

- Verify after PCI passthrough

```bash
lspci -nn | grep 089a
ls /dev/apex_0
```
