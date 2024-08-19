echo "------------------------ Updating network settings for VPN -----------------------"

/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File C:\Users\matthewt\netupdate-vpn.ps1' -Verb RunAs"

outputFile=/mnt/c/Users/matthewt/netupdate.txt

while [ ! -f "$outputFile" ]; do
  sleep 1
done  

cat $outputFile
echo ""
cp /mnt/c/Users/matthewt/resolv.conf /etc/resolv.conf
chmod 644 /etc/resolv.conf
sed -i 's/\r$//' /etc/resolv.conf
cat /etc/resolv.conf


echo "---------------------------- Network settings updated ----------------------------"
