# Mac Setup
Setup a MacOS based computer to seamlessly access homelab services, both remotely and locally. Also optimizes the Terminal app to access VM hosts and work on homelab code.

## Dependencies
- Install homebrew, xcode, pip and other dependencies
```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
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
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
wget https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/schemes/Solarized%20Dark%20Higher%20Contrast.itermcolors
brew tap homebrew/cask-fonts
brew install --cask font-meslo-lg-nerd-font

wget -O .vimrc https://raw.githubusercontent.com/amix/vimrc/master/vimrcs/basic.vim
```
- Configure iTerm ([src](https://medium.com/seokjunhong/customize-the-terminal-zsh-iterm2-powerlevel10k-complete-guide-for-beginners-35c4ba439055))

## Source code
- Install tools
```bash
brew install fd yq
pip3 install jinjanator jinjanator-plugin-ansible passlib
```

- Render source
```bash
cd ~/Documents
git clone {{ repo }} homelab
cd homelab
# Fill in personal details based on vars.template.yml
vim vars.yml
tools/render_src.sh ~/Documents/homelab-rendered

cd ~/Documents/homelab-rendered/src
cp macos/aliases.zsh ~/.oh-my-zsh/custom
cp macos/functions.zsh ~/.oh-my-zsh/custom
```

## Auto-switch DNS
[ref](https://apple.stackexchange.com/a/399571)
- Create network location
```bash
networksetup -createlocation Home populate
networksetup -switchtolocation Home
```
- Configure the desired DNS settings
  - Go To System Settings >> Wi-Fi >> details >> DNS
- Setup watcher
```bash
networksetup -switchtolocation Automatic
cp macos/vpn.sh /usr/local/bin
cp macos/detect_wifi_change.sh /usr/local/bin
cp macos/com.my.detect.wifi.change.plist ~/Library/LaunchAgents
launchctl load ~/Library/LaunchAgents/com.my.detect.wifi.change.plist
```
- Test by switching WiFi

## Static site tools and generator
- Install tools
```bash
brew install sass/sass/sass
# sass file.sass file.css

pip3 install mkdocs-material
# mkdocs new blog
# mkdocs build
```
