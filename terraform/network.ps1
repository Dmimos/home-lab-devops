param (
    [string]$SwitchName = "lab-switch",
    [string]$NatName = "lab-nat",
    [string]$GatewayIP = "192.168.50.1",
    [string]$VMIP = "192.168.50.20",
    [string]$Host1IP
)

$ErrorActionPreference = "Stop"

Write-Host "Configuring gateway IP on vEthernet ($SwitchName)..."
$adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
if ($adapter) {
    $currentIP = Get-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if (-not $currentIP -or $currentIP.IPAddress -ne $GatewayIP) {
        New-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -IPAddress $GatewayIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
    }
} else {
    Start-Sleep -Seconds 5
    New-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -IPAddress $GatewayIP -PrefixLength 24 -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "Creating NAT $NatName..."
$nat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if (-not $nat) {
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix "192.168.50.0/24" | Out-Null
}

Write-Host "Adding port mapping for SSH..."
$mapping = Get-NetNatStaticMapping -NatName $NatName -ErrorAction SilentlyContinue | Where-Object { $_.ExternalPort -eq 2222 }
if (-not $mapping) {
    Add-NetNatStaticMapping -NatName $NatName -Protocol TCP -ExternalIPAddress 0.0.0.0 -ExternalPort 2222 -InternalIPAddress $VMIP -InternalPort 22 | Out-Null
}

Write-Host "Configuring firewall rule for Host 1 ($Host1IP)..."
$rule = Get-NetFirewallRule -DisplayName "lab-mgmt-ssh-in" -ErrorAction SilentlyContinue
if (-not $rule) {
    New-NetFirewallRule -DisplayName "lab-mgmt-ssh-in" -Direction Inbound -Protocol TCP -LocalPort 2222 -RemoteAddress $Host1IP -Action Allow | Out-Null
}
Write-Host "Network setup complete."