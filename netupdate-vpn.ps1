#Updates interface metrics to set priority when VPN is connected and disconnected
Param ([string]$WindowsPath, [string]$Vpn)

$missingParams=$false
if ($WindowsPath -eq "") {
    Write-Host "WindowsPath cannot be empty."
    $missingParams=$true
} 
if ($Vpn -eq "") {
    Write-Host "Vpn cannot be empty."
    $missingParams=$true
}

if ($missingParams) {
    exit 1
}

$isVpn=""
$outputPath = "$WindowsPath\netupdate.txt"
if (Test-Path $outputPath) {
    Remove-Item $outputPath
}

$resolvPath = "$WindowsPath\resolv.conf"
if (Test-Path $resolvPath) {
    Remove-Item $resolvPath
}


$resolvContent = @()
$searchSuffixes = (Get-DnsClientGlobalSetting).SuffixSearchList
$highMetric = 6000

$wslMetricConnected = 20
$vpnMetricConnected = 10
$wifiMetricConnected = 15

$wslMetricDisconnected = 20
$wifiMetricDisconnected = 10

$wslAdapter = [int32](Get-NetAdapter -IncludeHidden | Where-Object { $_.Name -like "vEthernet*WSL*" } | Select -ExpandProperty ifIndex)
$vpnAdapter = [int32](Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$Vpn*" } | Select -ExpandProperty ifIndex)
$wifiAdapter = [int32](Get-NetAdapter | Where-Object { $_.Name -like "*Wi-Fi*" } | Select -ExpandProperty ifIndex)

$wslInterface4 = Get-NetIpInterface | Where-Object { $_.ifIndex -eq $wslAdapter -and $_.AddressFamily -eq "IPv4" }
$vpnInterface4 = Get-NetIpInterface | Where-Object { $_.ifIndex -eq $vpnAdapter -and $_.AddressFamily -eq "IPv4" }
$wifiInterface4 = Get-NetIpInterface | Where-Object { $_.ifIndex -eq $wifiAdapter -and $_.AddressFamily -eq "IPv4" }

$vpnInterface6 = Get-NetIpInterface | Where-Object { $_.ifIndex -match $vpnAdapter -and $_.AddressFamily -eq "IPv6" }
$wifiInterface6 = Get-NetIpInterface | Where-Object { $_.ifIndex -match $wifiAdapter -and $_.AddressFamily -eq "IPv6" }  

if ($vpnInterface4) {


	$isVpn = "VPN is Connected. Setting interface metrics"

        Set-NetIPInterface -InterfaceIndex $vpnInterface6.InterfaceIndex -InterfaceMetric $highMetric
        Set-NetIPInterface -InterfaceIndex $wifiInterface6.InterfaceIndex -InterfaceMetric $highMetric

        Set-NetIPInterface -InterfaceIndex $wslInterface4.InterfaceIndex -InterfaceMetric $wslMetricConnected
	Set-NetIPInterface -InterfaceIndex $vpnInterface4.InterfaceIndex -InterfaceMetric $vpnMetricConnected
	Set-NetIPInterface -InterfaceIndex $wifiInterface4.InterfaceIndex -InterfaceMetric $wifiMetricConnected

	$dnsAddresses = Get-NetAdapter | ?{ ($_.InterfaceDescription -like "*$Vpn*") } | Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses

        foreach ($address in $dnsAddresses) {
            $resolvContent += "nameserver $address"
        }
        $resolvContent += "nameserver 1.1.1.1"
        $resolvContent += "search $($searchSuffixes -join ' ')"
} else {

        $isVpn = "VPN is Disonnected. Setting interface metrics"

        Set-NetIPInterface -InterfaceIndex $wslInterface4.InterfaceIndex -InterfaceMetric $wslMetricDisconnected
        Set-NetIPInterface -InterfaceIndex $wifiInterface4.InterfaceIndex -InterfaceMetric $wifiMetricDisconnected

	Set-NetIPInterface -InterfaceIndex $wifiInterface6.InterfaceIndex -InterfaceMetric $wifiMetricDisconnected

	$dnsAddresses = Get-NetAdapter | ?{ -not ($_.InterfaceDescription -like "*$Vpn*") } | Get-DnsClientServerAddress | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -ExpandProperty ServerAddresses

	$resolvContent += "nameserver 1.1.1.1"
	foreach ($address in $dnsAddresses) {
	    $resolvContent += "nameserver $address"
	}
	$resolvContent += "search $($searchSuffixes -join ' ')"
}

#$resolvContent | Out-File -FilePath $resolvPath -Encoding UTF8 -NoNewline
[System.IO.File]::WriteAllLines($resolvPath, $resolvContent)

$var=C:\Windows\System32\wsl.exe -e /bin/bash --noprofile --norc -c "/sbin/ip -o -4 addr list eth0"
$wsl_addr = $var.split()[6].split('/')[0]

$var2 = C:\Windows\System32\wsl.exe -e /bin/bash --noprofile --norc -c "/sbin/ip -o route show table main default"
$wsl_gw = $var2.split()[2]

$ifindex = Get-NetRoute -DestinationPrefix $wsl_gw/32 | Select-Object -ExpandProperty "IfIndex"
$routemetric = Get-NetRoute -DestinationPrefix $wsl_gw/32 | Select-Object -ExpandProperty "RouteMetric"
 

route add $wsl_addr mask 255.255.255.255 $wsl_addr metric $routemetric if $ifindex

Write-Output $isVpn | Out-File -FilePath $outputPath -Append
Get-NetIPInterface | Sort-Object -Property InterfaceMetric | Format-Table -AutoSize | Out-File -FilePath $outputPath -Append

