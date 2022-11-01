# psiphon-tun2socks

Script to make Psiphon for Windows more like "real" VPN, but without using L2TP/IPSec mode. This way all system TCP and UDP traffic is captured and sent through a proxy. Psiphon on Android uses same approach.

This script utilizes badvpn tun2socks implementation and will not work with more modern Go-based project with same name, because I haven't figured out how to make UDP work there. Theoretically we can live without UDP using dns2socks instead of real DNS, but I haven't tried.

Also you should know, that ICMP will NOT work. So pings will fail, don't rely on it.

## Preparations

First copy 3rd-party/tun2socks-psiphon.exe to the same directory as psiphon-tun2socks.ps1. This executable is taken from official badvpn win32 binaries, you could build it by yourself if you want to.

To make this script work, we need to get tunnel interface. Simplest way is to install OpenVPN and find where it's installed (usually C:\Program Files\OpenVPN\bin) then you to execute following command from there:

`.\tapctl.exe create --name PsiphonVPN --hwid tap0901`

This have to be done only once, interface is surviving reboots.

Also you have to go to Psiphon settings and force port 12832 for SOCKS. Also you could disable disallowed traffic warning, because it definitely will appear, but will not affect usual workflow.

## How to use

Simply launch Psiphon, connect to server and launch psiphon-tun2socks.ps1. To exit you have to press Enter in command line window.

## How it works

1. Tunnel interface will be bound to Psiphon local SOCKS proxy.

2. Then we determine our local gateway.

3. Force ns1.google.com to go through it the tunnel interface

4. Determine our public Psiphon IP by asking ns1.google.com for it through address o-o.myaddr.l.google.com 

5. Force tunnel interface as default route, and public Psiphon IP through local gateway determined earlier.

6. Periodically "ping" 8.8.8.8 by resolving google.com (remember that we haven't got ICMP).

7. If fail, remove default route and retry from step 4. Failure could mean that our Psiphon address have changed.

8. If pressed Enter, cleanup and exit.