param([switch]$Check)

$ErrorActionPreference = 'Stop'
$server = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$python = Join-Path $server 'programs\python\python.exe'
$caddy = Join-Path $server 'programs\caddy.exe'
$originConfig = Join-Path $PSScriptRoot 'lan-diagnostic.Caddyfile'
$directTemplate = Join-Path $PSScriptRoot 'lan-background.Caddyfile'
$directConfig = Join-Path $PSScriptRoot 'lan-background-runtime.Caddyfile'
$tailnetTemplate = Join-Path $PSScriptRoot 'tailnet.Caddyfile'
$tailnetConfig = Join-Path $PSScriptRoot 'tailnet-runtime.Caddyfile'
$vendor = Join-Path $PSScriptRoot 'vendor'
$log = Join-Path $server 'logs\lan-autostart.log'

function Find-HomeAddress {
    $wifi = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.NdisPhysicalMedium -eq 9 })
    if (!$wifi.Count) { return }
    foreach ($adapter in $wifi) {
        $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.AddressState -eq 'Preferred' -and !$_.SkipAsSource -and $_.PrefixLength -ge 16 -and $_.PrefixLength -le 30 })
        foreach ($address in $addresses) {
            $octets = ([Net.IPAddress]::Parse($address.IPAddress)).GetAddressBytes()
            $private = $octets[0] -eq 10 -or
                ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -lt 32) -or
                ($octets[0] -eq 192 -and $octets[1] -eq 168)
            if (!$private) { continue }
            for ($index = 0; $index -lt $octets.Count; $index++) {
                $bits = [Math]::Max(0, [Math]::Min(8, $address.PrefixLength - 8 * $index))
                $octets[$index] = $octets[$index] -band ((255 -shl (8 - $bits)) -band 255)
            }
            return [pscustomobject]@{
                Address = $address.IPAddress
                Network = ($octets -join '.') + '/' + $address.PrefixLength
                Interface = $address.InterfaceIndex
            }
        }
    }
}

function Ensure-Component {
    param(
        [string]$Program, [string]$Marker, [string]$Arguments,
        [int]$Port, [string]$BindAddress, [string]$ExcludedMarker
    )
    $owned = @($processes | Where-Object {
        $_.ExecutablePath -eq $Program -and $_.CommandLine -and
        $_.CommandLine.IndexOf($Marker, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
        (!$ExcludedMarker -or $_.CommandLine.IndexOf($ExcludedMarker, [StringComparison]::OrdinalIgnoreCase) -lt 0)
    })
    foreach ($child in $owned) {
        $sameArguments = $Arguments -and $child.CommandLine.IndexOf($Arguments, [StringComparison]::OrdinalIgnoreCase) -ge 0
        $listening = !$Port -or ($listeners | Where-Object {
            $_.LocalPort -eq $Port -and $_.OwningProcess -eq $child.ProcessId -and $_.LocalAddress -eq $BindAddress
        })
        $starting = $child.CreationDate -gt (Get-Date).AddSeconds(-8)
        if ($sameArguments -and ($listening -or $starting)) { return }
        Stop-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
    }
    if (!$Arguments) { return }
    if ($Port -and (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @($BindAddress, '0.0.0.0', '::') })) {
        throw "Port $Port is occupied. No other listener was stopped."
    }
    Start-Process -FilePath $Program -ArgumentList $Arguments -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
}

function Find-TailnetAddress {
    Get-NetIPAddress -InterfaceAlias 'Tailscale' -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.AddressState -eq 'Preferred' -and $_.IPAddress -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.'
        } | Select-Object -First 1 -ExpandProperty IPAddress
}

function Write-RuntimeConfig {
    param([string]$Path, [string]$Content)
    if (!(Test-Path -LiteralPath $Path) -or [IO.File]::ReadAllText($Path) -ne $Content) {
        [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    }
}

$directPattern = [regex]::new('(?m)^(\s*bind )\d+(?:\.\d+){3}(?=\s*$)')
$template = [IO.File]::ReadAllText($directTemplate)
$tailnetSite = [IO.File]::ReadAllText($tailnetTemplate)
if ($directPattern.Matches($template).Count -ne 1) { throw 'Expected one bind address in the background transfer config.' }
if ($Check) {
    Find-HomeAddress
    Find-TailnetAddress
    return
}

$lastError = ''
$lastBinding = $null
while ($true) {
    try {
        $lanRoute = Find-HomeAddress
        $processes = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='caddy.exe'")
        $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object {
            $_.LocalPort -in 18113,18115,18116,18117
        })
        Ensure-Component $python ' -m Server.http_service ' "-B -m Server.http_service --root $server" 18115 '127.0.0.1'
        Ensure-Component $caddy $originConfig "run --config $originConfig --adapter caddyfile" 18116 '127.0.0.1'
        $gatewayArgs = $announcementArgs = $backgroundArgs = $address = ''
        if ($lanRoute) {
            $address = $lanRoute.Address
            $gatewayArgs = "-B -m Server.lan_gateway --address $address --network $($lanRoute.Network) --interface $($lanRoute.Interface) --loopback-origin-port 18116"
            $announcementArgs = "-B -m Server.lan_dns --address $address --port 18113 --vendor $vendor"
            $backgroundArgs = "run --config $directConfig --adapter caddyfile"
            Write-RuntimeConfig $directConfig ($directPattern.Replace($template, '${1}' + $address))
        }
        Ensure-Component $python ' -m Server.lan_gateway ' $gatewayArgs 18113 $address ' --tailnet'
        Ensure-Component $caddy $directConfig $backgroundArgs 18117 $address
        Ensure-Component $python ' -m Server.lan_dns ' $announcementArgs
        $tailAddress = Find-TailnetAddress
        $tailGatewayArgs = $tailTLSArgs = ''
        if ($tailAddress) {
            Write-RuntimeConfig $tailnetConfig ($tailnetSite.Replace('__TAILNET_ADDRESS__', $tailAddress))
            $tailGatewayArgs = "-B -m Server.lan_gateway --address $tailAddress --network 100.64.0.0/10 --tailnet"
            $tailTLSArgs = "run --config $tailnetConfig --adapter caddyfile"
        }
        Ensure-Component $caddy $tailnetConfig $tailTLSArgs 18117 $tailAddress
        Ensure-Component $python ' --tailnet' $tailGatewayArgs 18113 $tailAddress
        $binding = if ($lanRoute) { "$address on interface $($lanRoute.Interface)" } else { 'waiting for Wi-Fi' }
        if ($tailAddress) { $binding += " and Tailscale $tailAddress" }
        if ($binding -ne $lastBinding) {
            Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) PhoneDisk LAN services $binding"
            $lastBinding = $binding
        }
        $lastError = ''
    } catch {
        if ($_.Exception.Message -ne $lastError) {
            $lastError = $_.Exception.Message
            Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) $lastError"
        }
    }
    Start-Sleep -Seconds 8
}
