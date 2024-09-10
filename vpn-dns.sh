#!/bin/bash

read -p "Update network settings? [Y/n]: " shouldUpdate
shouldUpdate=${shouldUpdate:-Y}

if [[ "$shouldUpdate" == "n" || "$shouldUpdate" == "N" ]]; then
  exit 0
fi

vpn=PANGP

wslPath=$1
if [ -z "$1" ]; then
  read -p "Please provide WSL script path [/mnt/c/Users/$(whoami)]: " wslPath
  wslPath=${wslPath=-/mnt/c/Users/$(whoami)}
fi
echo "Using WSL path: $wslPath"

winPath=$2

if [ -z "$2" ]; then
  read -p "Please provide Windows script path [C:\\Users\\$(whoami)]: " winPath
  winPath=${winPath=-"C:\\Users\\$(whoami)"}
fi
echo "Using Windows path: $winPath"

outputFile=$wslPath/netupdate.txt
resolvFile=$wslPath/resolv.conf

if [[ -e $outputFile ]]; then
  rm $outputFile
fi
if [[ -e $resolvFile ]]; then
  rm $resolvFile
fi

echo "------------------------ Updating network settings for VPN -----------------------"

/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ${winPath}\\netupdate-vpn.ps1 -WindowsPath ${winPath} -Vpn ${vpn}' -Verb RunAs"


while [ ! -f "$outputFile" ] || [ ! -s "$outputFile" ]; do
  sleep 1
done  

cat $outputFile
echo ""

while [ ! -f "$resolvFile" ]; do
  sleep 1
done

cp $resolvFile /etc/resolv.conf
chmod 644 /etc/resolv.conf
sed -i 's/\r$//' /etc/resolv.conf
cat /etc/resolv.conf


echo "---------------------------- Network settings updated ----------------------------"
