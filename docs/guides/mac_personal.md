# Mac Setup
Setup a MacOS based computer to seamlessly access homelab services, both remotely and locally. Also optimizes the Terminal app to access VM hosts and work on homelab code.

## Dependencies
- Install xcode, homebrew, pip, git and other dependencies
```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
python3 --version
python3 -m ensurepip --upgrade
git --version
```

## Terminal
- Install Iterm2, zsh, oh-my-zsh, powerlevel10k ([src](https://medium.com/seokjunhong/customize-the-terminal-zsh-iterm2-powerlevel10k-complete-guide-for-beginners-35c4ba439055))
```bash
brew install zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
```
- `vim ~/.zshrc`
```
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(zsh-autosuggestions zsh-syntax-highlighting git)
```
- Install [color scheme](https://iterm2colorschemes.com/) and [fonts](https://www.nerdfonts.com/)
```bash
brew install wget
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
wget https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/Solarized%20Dark%20Higher%20Contrast.itermcolors
brew install --cask font-meslo-lg-nerd-font

wget -O .vimrc https://raw.githubusercontent.com/amix/vimrc/master/vimrcs/basic.vim
```
- In iTerm, configure [natural key bindings](https://apple.stackexchange.com/questions/136928/using-alt-cmd-right-left-arrow-in-iterm)

## Source code
- Install tools
```bash
brew install fd yq yamllint
pip3 install jinjanator jinjanator-plugin-ansible passlib "bcrypt==4.0.1"
curl -fsSL https://claude.ai/install.sh | bash
```

- Render source
```bash
cd ~/Documents
git clone {{ repo }} homelab
cd homelab
# Fill in personal details based on vars.template.yml
vim vars.yml
tools/render_src.sh ../homelab-rendered

cd ../homelab-rendered/src
cp debian/aliases.zsh ~/.oh-my-zsh/custom
cp debian/functions.zsh ~/.oh-my-zsh/custom
```

## Auto-switch DNS
[ref](https://apple.stackexchange.com/a/399571)
- Create network location
```bash
networksetup -createlocation Home populate
networksetup -switchtolocation Home
```
- Configure the desired DNS settings
  - Go To System Settings >> Wi-Fi >> Details >> DNS
    - Under DNS Servers, add {{ wifi.trusted.subnet }}.1 and delete other IPs
    - Under Search Domains, add {{ site.url }}
- Setup watcher
```bash
networksetup -switchtolocation Automatic
sudo cp macos/vpn.sh /usr/local/bin
sudo cp macos/detect_wifi_change.sh /usr/local/bin
cp macos/com.my.detect.wifi.change.plist ~/Library/LaunchAgents
launchctl load ~/Library/LaunchAgents/com.my.detect.wifi.change.plist
```
- Test by switching WiFi networks, confirm location changes
  - `networksetup -getcurrentlocation`
