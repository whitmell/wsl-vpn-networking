# WSL VPN Networking

Runs bash and powershell commands to prioritize network adapters and set resolv.conf to allow internal and external network traffic to WSL2 instance while on VPN.

# How it works
The script utilizes a Powershell script to change the priority of the VPN network adapter, Wifi network adapter, and WSL network adapter to allow traffic internally on the VPN network as well as external internet traffic. It also retrieves DNS servers and search domains from the VPN and creates /etc/resolv.conf within WSL.  The install script will place a file in /etc/profile.d to run the script every time a WSL session is opened.  

# Installation

Download install.sh

```
wget https://raw.githubusercontent.com/whitmell/wsl-vpn-networking/main/install.sh  && chmod +x install.sh
```

Run as sudo, enter your WSL user, Windows user (uses WSL user by default), and a search string unique to your VPN network adapter.  The script searches for the string in the InterfaceDescription property.  You can view the InterfaceDescription for all network adapters by running "Get-NetAdapter" in powershell.

```
$ sudo ./install.sh
WSL user: whitmell
Windows user [whitmell]: 
VPN Search string [PANGP]
WSL User: whitmell
Windows User: whitmell
WSL Path: /mnt/c/Users/whitmell
Windows Path: C:/Users/whitmell
VPN Search string: PANGP
Creating vpn-dns.sh
Creating netupdate-vpn.ps1
Creating startup script
Creating sudoers file
WSL VPN Network Updater has been installed
```

# Uninstalling

Run cleanup.sh as sudo to remove all files

```
sudo ./cleanup.sh
```