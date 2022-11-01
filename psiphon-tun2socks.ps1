function CleanUp {
Write-Output "Cleaning up..."
Write-Output "Stopping tun2socks..."
Stop-Process -Name $tun2socks_exec

Write-Output "Cleaning up routes..."
Remove-NetIPAddress -InterfaceAlias $interface_name -IPAddress $virtual_ip -PrefixLength 30 -Confirm:$false  -ErrorAction SilentlyContinue | Out-Null
RemoveRemoteGatewayRoute
Remove-NetRoute -DestinationPrefix $resolver_ip/32 -NextHop $virtual_gw -InterfaceAlias $interface_name -Confirm:$false  -ErrorAction SilentlyContinue | Out-Null
RemoveGateway
}

function ResolveRemoteGateway {
	$result=(Resolve-DnsName -Name o-o.myaddr.l.google.com -Type TXT -Server $resolver_ip).strings[0]
	return $result
}

function InsertRemoteGatewayRoute {
	New-NetRoute -DestinationPrefix $remote_gateway/32 -NextHop $local_gateway -InterfaceAlias $local_gateway_alias | Out-Null
}

function RemoveRemoteGatewayRoute {
	Remove-NetRoute -DestinationPrefix $remote_gateway/32 -NextHop $local_gateway -InterfaceAlias $local_gateway_alias -Confirm:$false  -ErrorAction SilentlyContinue | Out-Null
}

function AddGateway {
	New-NetRoute -DestinationPrefix 0.0.0.0/0 -NextHop $virtual_gw -InterfaceAlias $interface_name -RouteMetric 1 | Out-Null
}

function RemoveGateway {
	Remove-NetRoute -DestinationPrefix 0.0.0.0/0 -NextHop $virtual_gw -InterfaceAlias $interface_name -Confirm:$false  -ErrorAction SilentlyContinue | Out-Null
}

function PrepareStartup {
	Remove-NetRoute -InterfaceAlias $interface_name -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}

Write-Output "Welcome to Psiphon-tun2socks!"

$psiphon_processname="psiphon-tunnel-core"
if(-Not(Get-Process|Where-Object -Property ProcessName -Eq $psiphon_processname)) {
	Write-Output "Psiphon not connected! Please connect BEFORE launching script!"
	Write-Output "Exiting..."
	Exit
}

$tun2socks_exec="tun2socks-psiphon"

$port= "12832"

$local_gateway=""
$local_gateway_alias=""

$tun_driver="tap0901"
$interface_name="PsiphonVPN"
$virtual_ip="10.199.199.253"
$virtual_gw="10.199.199.254"
$virtual_net="10.199.199.252"
$virtual_netmask="255.255.255.252"
$virtual_prefix="30"

PrepareStartup

$local_gateway = (Get-NetIPConfiguration|Where-Object -Property IPv4DefaultGateway)[0].IPv4DefaultGateway.NextHop.toString()
$local_gateway_alias = (Get-NetIPConfiguration|Where-Object -Property IPv4DefaultGateway)[0].IPv4DefaultGateway.InterfaceAlias.toString()
Write-Output "Local Gateway: " $local_gateway
Write-Output "Local Gateway Interface:" $local_gateway_alias



$tun2socks_args="--socks-server-addr 127.0.0.1`:$port --udpgw-remote-server-addr 127.0.0.1`:7300 --netif-ipaddr $virtual_gw --netif-netmask $virtual_netmask --tundev $tun_driver`:$interface_name`:$virtual_ip`:$virtual_net`:$virtual_netmask"

Write-Output "Starting tun2socks..."
Start-Process -FilePath $tun2socks_exec -ArgumentList $tun2socks_args

Write-Output "Started, waiting.."
Start-Sleep -s 1

Write-Output "Assigning IP to TUN..."
New-NetIPAddress -InterfaceAlias $interface_name -IPAddress $virtual_ip -PrefixLength 30 | Out-Null

Write-Output "Assigned, waiting..."
Start-Sleep -s 5

$remote_gateway=""
#$psiphon_pid=""

#$psiphon_pid=(Get-Process|Where-Object -Property ProcessName -Eq $psiphon_processname)[0].ID.toString()
#$remote_gateway=(Get-NetTCPConnection|Where-Object -Property OwningProcess -Eq $psiphon_pid|Where-Object -Property State -Eq "Established")[0].RemoteAddress.toString()

#Write-Output $psiphon_pid
#Write-Output $remote_gateway

#If ($remote_gateway -eq "127.0.0.1") {
#	CleanUp
#	Exit
#}

$resolver_name="ns1.google.com"
$resolver_ip=""
Write-Output "Resolver used:" $resolver_name
$resolver_ip=(Resolve-DnsName -Name $resolver_name -Type A -Server 8.8.8.8).IpAddress
Write-Output "Resolver IP:" $resolver_ip
New-NetRoute -DestinationPrefix $resolver_ip/32 -NextHop $virtual_gw -InterfaceAlias $interface_name | Out-Null

try {
	$remote_gateway=ResolveRemoteGateway
	Write-Output "External address:" $remote_gateway
	InsertRemoteGatewayRoute
}
catch {
	Write-Output "Cannot found external address!"
	Write-Output "Try to restart Psiphon and start the script again."
	Write-Output "Exiting..."
	CleanUp
	Exit
}

Write-Output "Installing routes..."
AddGateway
Set-DnsClientServerAddress -InterfaceAlias $interface_name -ServerAddresses ("8.8.8.8")

Write-Output "Starting network status monitoring. To exit press Enter"
do
{
	Write-Output "Checking..."
	try {
		if ($remote_gateway -Eq "") {
			Write-Output "No external address!"
			Throw
		}
		Resolve-DnsName google.com -Server 8.8.8.8 -Type A -ErrorAction Stop | Out-Null
		Write-Output "OK"
	}
	catch{
		Write-Output "Error. Trying to recover..."
		if(-Not(Get-Process|Where-Object -Property ProcessName -Eq $psiphon_processname)) {
			Write-Output "Psiphon not connected! Please connect again and restart script!"
			Write-Output "Exiting..."
			CleanUp
			Exit
		}
		RemoveGateway
		Start-Sleep -Seconds 10
		RemoveRemoteGatewayRoute
		try {
		$remote_gateway=ResolveRemoteGateway
		Write-Output "New external address:" $remote_gateway
		InsertRemoteGatewayRoute
		AddGateway
		}
		catch {
			Write-Output "Cannot found external address!"
			$remote_gateway=""
		}
	}
	Start-Sleep -Seconds 10
} until ([System.Console]::KeyAvailable)

CleanUp

Write-Output "Exiting..."
Exit
