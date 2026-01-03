# Gaming setup
Guide to stream games from the windows VM to my living room TV.

- First stand up the [Windows VM](./vm_windows.md)
- And the [Raspberry Pi](./rpi.md) client for the TV

### Windows streaming server and game platforms
- Install [ViGEmBus](https://github.com/ViGEm/ViGEmBus)
- Install [Playnite](https://playnite.link/)
- Install [ChangeScreenResolution.exe](https://tools.taubenkorb.at/change-screen-resolution/)
- Install [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/en/latest/about/installation.html)
  - Add Playnite as a cmd: `"C:\Users\{{ username }}\AppData\Local\Playnite\Playnite.FullscreenApp.exe" --hidesplashscreen`
  - Run PowerShell cmds:
```PowerShell
cd "C:\Program Files\Sunshine\scripts"
./add-firewall-rule.bat
./install-service.bat
```
- Install [Moonlight](https://github.com/moonlight-stream/moonlight-qt/releases) on Mac, Raspberry Pi
- Install Oculus App
  - Run as admin: `C:\Program Files\Oculus\Support\oculus-runtime\OVRServer_x64.exe`
  - Start the App
  - [Enable mDNS reflection](./pfsense.md)
  - On Quest 2, Settings > System > Link, enable Air link, pair with computer
- Install Yuzu, Ryujinx
  - Download [keys](https://theprodkeys.com/yuzu-encryption-keys-are-missing/) and copy to correct folder location
  - Import into Playnite
- Install Dolphin, import into Playnite

### Apple TV client
- Install Moonlight from the App Store
- Tweak the [settings](https://www.reddit.com/r/appletv/comments/nklgcl/any_apple_tv_4k_2021_owners_that_have_tried/)
- Attempt to connect to the gaming VM. Open the Sunshine web UI and enter in the pairing code.
- Pair xbox controller via bluetooth

### Raspberry Pi client
- Enable HEVC, HDR
  - `vim /Volumes/bootfs/config.txt`
```
# may be outdated
dtoverlay=rpivid-v4l2

# dtoverlay=vc4-kms-v3d
dtoverlay=vc4-fkms-v3d

gpu_mem=128
```
- Install Moonlight QT ([notes](https://github.com/moonlight-stream/moonlight-qt/issues/967))
```bash
curl -1sLf 'https://dl.cloudsmith.io/public/moonlight-game-streaming/moonlight-qt/setup.deb.sh' | distro=raspbian codename=buster sudo -E bash
sudo apt install -y moonlight-qt vim less iproute2 git netcat
sudo apt update
sudo apt upgrade
sudo vim /etc/systemd/system/moonlight.service
sudo systemctl enable moonlight.service
```
- In the Moonlight GUI, set resolution to 1080p, refresh rate to 60Hz

- Buy Xbox S/X controllers (model [1914](https://boilingsteam.com/xbox-one-controller-a-perfected-xbox-360-gamepad/)) and [dongle](https://www.newegg.com/p/2NG-015J-00004?item=9SIB5YAK5E3117)
- Install [xone](https://github.com/dlundqvist/xone) driver
```bash
# Plugin in dongle
git clone https://github.com/dlundqvist/xone
cd xone
sudo ./install.sh --release
sudo xow-get-firmware.sh --skip-disclaimer
```
- Power on controllers, [pair](https://support.xbox.com/en-US/help/hardware-network/controller/connect-xbox-wireless-controller-to-pc)
  - Put dongle into pairing mode
```bash
echo 1 | sudo tee /sys/bus/usb/drivers/xone-dongle/*/pairing
```