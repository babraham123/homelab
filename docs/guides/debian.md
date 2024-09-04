# Debian Linux setup
Initial setup for any Debian Linux instance. Configures the shell, ssh access and useful utilities.

- First do the basic [VM setup](./vm.md)

## Packages
- If graphical install, open Terminal app. Otherwise just ssh in as root.
```bash
su
usermod -aG sudo {{ username }}
apt install -y ssh
```
- Fix deb repository, [src](https://it42.cc/2019/10/14/fix-proxmox-repository-is-not-signed/) 
	- `nano /etc/apt/sources.list`
	- add `contrib non-free non-free-firmware` to all Debian sources
- Install basics
```bash
apt update && apt upgrade
apt install -y sudo zsh vim iproute2 git less curl wget zip unzip ethtool jq unattended-upgrades ufw
chsh -s /bin/zsh

# enable firewall
ufw allow ssh
ufw enable

adduser {{ username }}
usermod -aG sudo {{ username }}
exit
```
- Reconnect as {{ username }}
- Configure updates
	- Uncomment "-updates": `sudo vim /etc/apt/apt.conf.d/50unattended-upgrades`

## SSH
- Set timezone
  - `sudo timedatectl set-timezone {{ personal.timezone }}`
- Change hostname
	- `sudo hostnamectl set-hostname SUBDOMAIN`
	- `sudo vim /etc/hosts`, add `127.0.1.1    SUBDOMAIN.{{ site.url }}    SUBDOMAIN`
- Lock down SSH
	- `sudo vim /etc/ssh/sshd_config`
```
PermitRootLogin no
```
- Generate SSH key, set correct SUBDOMAIN
```bash
ssh-keygen -t ed25519 -C "{{ username }}@SUBDOMAIN.{{ site.url }}"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

## ZSH
- Install tools ([src](https://gist.github.com/sinadarvi/7b7178cb3cf9a605ab04700cae05287a))
```bash
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"

sudo apt install -y fonts-powerline fontconfig
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k

mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
wget https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip
unzip Meslo.zip
rm Meslo.zip
fc-cache -fv
cd ~
wget -O .vimrc https://raw.githubusercontent.com/amix/vimrc/master/vimrcs/basic.vim
echo 'export EDITOR="vim"' >> ~/.zshrc
```
- `vim ~/.zshrc`
```
...
ZSH_THEME="powerlevel10k/powerlevel10k"
...
plugins=(zsh-autosuggestions zsh-syntax-highlighting git)
```
- Copy files from source repo, under `src/debian`
  - `vim ~/.oh-my-zsh/custom/aliases.zsh`
  - `vim ~/.oh-my-zsh/custom/functions.zsh`
  - `sudo vim /root/.zshrc`

- Logout and log back in. Configure oh-my-zsh
	- Answers: `yyyy211n1311111y1y`
