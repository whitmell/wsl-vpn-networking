#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root. Please run with sudo." >&2
  exit 1
fi


if [ -z "$1" ]; then
  read -p "WSL user: " WSL_USER
fi

if [ -z "$WSL_USER" ]; then
  echo "No user provided. Exiting."
  exit 1
fi

if [ -z "$2" ]; then
  read -p "Windows user [$WSL_USER]: " WIN_USER
  WIN_USER=${WIN_USER:-$WSL_USER}
fi

if [ -z "$3" ]; then
  read -p "VPN Search string [PANGP]" VPN_STR
  VPN_STR=${VPN_STR:-PANGP}
fi

WIN_PATH="C:/Users/$WIN_USER"
WSL_PATH="/mnt/c/Users/$WIN_USER"

echo "WSL User: $WSL_USER"
echo "Windows User: $WIN_USER"
echo "WSL Path: $WSL_PATH"
echo "Windows Path: $WIN_PATH"
echo "VPN Search string: $VPN_STR"

# Create vpn-dns.sh
echo "Creating vpn-dns.sh"
cat << EOF > vpn-dns.sh
#!/bin/bash

read -p "Update network settings? [Y/n]: " shouldUpdate
shouldUpdate=\${shouldUpdate:-Y}

if [[ "\$shouldUpdate" == "n" || "\$shouldUpdate" == "N" ]]; then
  exit 0
fi

vpn=$VPN_STR

wslPath=\$1
if [ -z "\$1" ]; then
  read -p "Please provide WSL script path [/mnt/c/Users/\$(whoami)]: " wslPath
  wslPath=\${wslPath:-/mnt/c/Users/\$(whoami)}
fi
echo "Using WSL path: \$wslPath"

winPath=\$2

if [ -z "\$2" ]; then
  read -p "Please provide Windows script path [C:/Users/\$(whoami)]: " winPath
  winPath=\${winPath:-"C:/Users/$(whoami)"}
fi
echo "Using Windows path: \$winPath"

outputFile=\$wslPath/netupdate.txt
resolvFile=\$wslPath/resolv.conf

if [[ -e \$outputFile ]]; then
  rm \$outputFile
fi
if [[ -e \$resolvFile ]]; then
  rm \$resolvFile
fi

echo "------------------------ Updating network settings for VPN -----------------------"

/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \${winPath}/netupdate-vpn.ps1 -WindowsPath \${winPath} -Vpn \${vpn}' -Verb RunAs"


while [ ! -f "\$outputFile" ] || [ ! -s "\$outputFile" ]; do
  sleep 1
done  

cat \$outputFile
echo ""

while [ ! -f "\$resolvFile" ]; do
  sleep 1
done

cp \$resolvFile /etc/resolv.conf
chmod 644 /etc/resolv.conf
sed -i 's/\r$//' /etc/resolv.conf
cat /etc/resolv.conf


echo "---------------------------- Network settings updated ----------------------------"
EOF

# Create netupdate-vpn.ps1
echo "Creating netupdate-vpn.ps1"
cat << EOF > netupdate-vpn.ps1
#Updates interface metrics to set priority when VPN is connected and disconnected
Param ([string]\$WindowsPath, [string]\$Vpn)

\$missingParams=\$false
if (\$WindowsPath -eq "") {
    Write-Host "WindowsPath cannot be empty."
    \$missingParams=\$true
} 
if (\$Vpn -eq "") {
    Write-Host "Vpn cannot be empty."
    \$missingParams=\$true
}

if (\$missingParams) {
    exit 1
}

\$isVpn=""
\$outputPath = "\$WindowsPath\netupdate.txt"
if (Test-Path \$outputPath) {
    Remove-Item \$outputPath
}

\$resolvPath = "\$WindowsPath\resolv.conf"
if (Test-Path \$resolvPath) {
    Remove-Item \$resolvPath
}


\$resolvContent = @()
\$searchSuffixes = (Get-DnsClientGlobalSetting).SuffixSearchList
\$highMetric = 6000

\$wslMetricConnected = 20
\$vpnMetricConnected = 10
\$wifiMetricConnected = 15

\$wslMetricDisconnected = 20
\$wifiMetricDisconnected = 10

\$wslAdapter = [int32](Get-NetAdapter -IncludeHidden | Where-Object { \$_.Name -like "vEthernet*WSL*" } | Select -ExpandProperty ifIndex)
\$vpnAdapter = [int32](Get-NetAdapter | Where-Object { \$_.InterfaceDescription -like "*\$Vpn*" } | Select -ExpandProperty ifIndex)
\$wifiAdapter = [int32](Get-NetAdapter | Where-Object { \$_.Name -like "*Wi-Fi*" } | Select -ExpandProperty ifIndex)

\$wslInterface4 = Get-NetIpInterface | Where-Object { \$_.ifIndex -eq \$wslAdapter -and \$_.AddressFamily -eq "IPv4" }
\$vpnInterface4 = Get-NetIpInterface | Where-Object { \$_.ifIndex -eq \$vpnAdapter -and \$_.AddressFamily -eq "IPv4" }
\$wifiInterface4 = Get-NetIpInterface | Where-Object { \$_.ifIndex -eq \$wifiAdapter -and \$_.AddressFamily -eq "IPv4" }

\$vpnInterface6 = Get-NetIpInterface | Where-Object { \$_.ifIndex -match \$vpnAdapter -and \$_.AddressFamily -eq "IPv6" }
\$wifiInterface6 = Get-NetIpInterface | Where-Object { \$_.ifIndex -match \$wifiAdapter -and \$_.AddressFamily -eq "IPv6" }  

if (\$vpnInterface4) {


	\$isVpn = "VPN is Connected. Setting interface metrics"

        Set-NetIPInterface -InterfaceIndex \$vpnInterface6.InterfaceIndex -InterfaceMetric \$highMetric
        Set-NetIPInterface -InterfaceIndex \$wifiInterface6.InterfaceIndex -InterfaceMetric \$highMetric

        Set-NetIPInterface -InterfaceIndex \$wslInterface4.InterfaceIndex -InterfaceMetric \$wslMetricConnected
	Set-NetIPInterface -InterfaceIndex \$vpnInterface4.InterfaceIndex -InterfaceMetric \$vpnMetricConnected
	Set-NetIPInterface -InterfaceIndex \$wifiInterface4.InterfaceIndex -InterfaceMetric \$wifiMetricConnected

	\$dnsAddresses = Get-NetAdapter | ?{ (\$_.InterfaceDescription -like "*\$Vpn*") } | Get-DnsClientServerAddress | Where-Object { \$_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses

        foreach (\$address in \$dnsAddresses) {
            \$resolvContent += "nameserver \$address"
        }
        \$resolvContent += "nameserver 1.1.1.1"
        \$resolvContent += "search \$(\$searchSuffixes -join ' ')"
} else {

        \$isVpn = "VPN is Disonnected. Setting interface metrics"

        Set-NetIPInterface -InterfaceIndex \$wslInterface4.InterfaceIndex -InterfaceMetric \$wslMetricDisconnected
        Set-NetIPInterface -InterfaceIndex \$wifiInterface4.InterfaceIndex -InterfaceMetric \$wifiMetricDisconnected

	Set-NetIPInterface -InterfaceIndex \$wifiInterface6.InterfaceIndex -InterfaceMetric \$wifiMetricDisconnected

	\$dnsAddresses = Get-NetAdapter | ?{ -not (\$_.InterfaceDescription -like "*\$Vpn*") } | Get-DnsClientServerAddress | Where-Object { \$_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses

	\$resolvContent += "nameserver 1.1.1.1"
	foreach (\$address in \$dnsAddresses) {
	    \$resolvContent += "nameserver \$address"
	}
	\$resolvContent += "search \$(\$searchSuffixes -join ' ')"
}

#\$resolvContent | Out-File -FilePath \$resolvPath -Encoding UTF8 -NoNewline
[System.IO.File]::WriteAllLines(\$resolvPath, \$resolvContent)

\$var=C:\Windows\System32\wsl.exe -e /bin/bash --noprofile --norc -c "/sbin/ip -o -4 addr list eth0"
\$wsl_addr = \$var.split()[6].split('/')[0]

\$var2 = C:\Windows\System32\wsl.exe -e /bin/bash --noprofile --norc -c "/sbin/ip -o route show table main default"
\$wsl_gw = \$var2.split()[2]

\$ifindex = Get-NetRoute -DestinationPrefix \$wsl_gw/32 | Select-Object -ExpandProperty "IfIndex"
\$routemetric = Get-NetRoute -DestinationPrefix \$wsl_gw/32 | Select-Object -ExpandProperty "RouteMetric"
 

route add \$wsl_addr mask 255.255.255.255 \$wsl_addr metric \$routemetric if \$ifindex

Write-Output \$isVpn | Out-File -FilePath \$outputPath -Append
Get-NetIPInterface | Sort-Object -Property InterfaceMetric | Format-Table -AutoSize | Out-File -FilePath \$outputPath -Append
EOF

# Create startup script
echo "Creating startup script"
cat << EOF > vpn-startup.sh
#!/bin/bash
sudo /usr/local/bin/vpn-dns.sh "$WSL_PATH" "$WIN_PATH"
EOF

# Create sudoers file
echo "Creating sudoers file"
cat << EOF > 010-$WSL_USER-vpn-dns
$WSL_USER ALL=(ALL) NOPASSWD: /usr/local/bin/vpn-dns.sh
EOF

chmod +x vpn-dns.sh
chmod o+r vpn-startup.sh
chmod +x netupdate-vpn.ps1

chown $WSL_USER:$WSL_USER vpn-dns.sh
chown $WSL_USER:$WSL_USER netupdate-vpn.ps1

if [ ! -d /etc/profile.d ]; then
  mkdir /etc/profile.d
fi

if [ ! -d /etc/sudoers.d ]; then
  mkdir /etc/sudoers.d
fi

mv vpn-dns.sh /usr/local/bin/
mv netupdate-vpn.ps1 "$WSL_PATH"
mv vpn-startup.sh /etc/profile.d/
mv "010-$WSL_USER-vpn-dns" /etc/sudoers.d/

echo "WSL VPN Network Updater has been installed"