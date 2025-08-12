# Development desktop setup
Guide to create the devtop VM. It's intended as an environment for general software development and the execution of AI models.
TODO: Add vscode, language scripts, remote desktop, model management

- First setup [Debian Linux](./debian.md)

## Passthrough the GPU
- Disable secure boot, [vid](https://www.youtube.com/watch?v=js_Xoa0f8zM)

- Install Nvidia drivers using the [GPU guide](./gpu.md)

- Passthrough the GPU, using the [Proxmox guide](./proxmox.md)

- Additional tools
```bash
echo 'export PATH=/usr/local/cuda-12.4/bin${PATH:+:${PATH}}' >> ~/.zshrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.4/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.zshrc
source ~/.zshrc
sudo apt install -y build-essential python3-pip g++ freeglut3-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libfreeimage-dev libglfw3-dev
```
