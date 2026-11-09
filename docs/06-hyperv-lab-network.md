# Hyper-V Lab Network and the First VM

## Goal
Prepare Host 2 as the virtualization host for the lab:

- an isolated virtual network with fixed addresses and outbound internet access;
- a predictable storage layout for virtual machines and installer images;
- the first virtual machine, `mgmt`, reachable from Host 1 through a single controlled entry point.

## Environment

| Item | Value |
|---|---|
| Host | Host 2 |
| OS | Windows 11 Pro (10.0.26200) with Hyper-V enabled |
| CPU / RAM | Core i7-9700K / about 16 GiB |
| Storage | Samsung SSD 860 EVO 1 TB (SATA), system volume `C:` |
| Host network | Wired Ethernet, address reserved on the home router |
| Client | Host 1, address reserved on the home router |
| Guest OS | Ubuntu Server 26.04.1 LTS |

## Initial State
Read-only inventory with PowerShell before any change showed:

- Hyper-V feature enabled, no virtual machines.
- A single virtual switch, `Default Switch`, and no NAT networks.
- No OpenSSH server on Host 2.

The `Default Switch` was left untouched. Its addressing is managed automatically and can change between reboots, so it cannot hold fixed lab addresses.

## Design

| Element | Decision |
|---|---|
| Virtual switch | Dedicated internal switch `lab-switch` |
| Lab subnet | `192.168.50.0/24`; Host 2 is the gateway at `192.168.50.1` |
| Outbound access | Windows NAT `lab-nat` for the whole subnet |
| Inbound access | One static port mapping: `Host 2:2222` to `mgmt:22` |
| Firewall | Inbound rule for port 2222, restricted to the address of Host 1 |

The lab network stays isolated from the home network. Routing the lab subnet from the home LAN was not used because it needs a static route and changes outside Host 2; a single port mapping gives one controlled entry point instead.

Address plan:

| Address | Use | Status |
|---|---|---|
| `192.168.50.1` | Host 2 (gateway) | In use |
| `192.168.50.10` | Kubernetes node | Reserved |
| `192.168.50.20` | `mgmt` | In use |
| `192.168.50.30` | Monitoring | Reserved |

## Procedure
All commands run in PowerShell as administrator on Host 2.

### Step 1: Storage Layout
```powershell
New-Item -ItemType Directory -Path C:\HyperV\VMs,C:\HyperV\Disks,C:\HyperV\ISO
Set-VMHost -VirtualMachinePath C:\HyperV\VMs -VirtualHardDiskPath C:\HyperV\Disks
Get-VMHost | Select-Object VirtualHardDiskPath,VirtualMachinePath
```

| Path | Content |
|---|---|
| `C:\HyperV\VMs` | VM configuration files |
| `C:\HyperV\Disks` | Virtual hard disks (VHDX) |
| `C:\HyperV\ISO` | Installer images |

A folder on the existing SSD was chosen over shrinking the system volume: it avoids changing the partition table of the Windows disk, and dynamically expanding disks with fixed maximum sizes keep the usage predictable.

### Step 2: Virtual Switch and NAT
```powershell
New-VMSwitch -Name lab-switch -SwitchType Internal
New-NetIPAddress -InterfaceAlias "vEthernet (lab-switch)" -IPAddress 192.168.50.1 -PrefixLength 24
New-NetNat -Name lab-nat -InternalIPInterfaceAddressPrefix 192.168.50.0/24
```

Verification:

```powershell
Get-VMSwitch
Get-NetIPAddress -InterfaceAlias "vEthernet (lab-switch)" -AddressFamily IPv4
Get-NetNat
```

Expected: switch `lab-switch` of type Internal, address `192.168.50.1/24` in state `Preferred`, and NAT `lab-nat` active on `192.168.50.0/24`. The temporary `Tentative` and `Invalid` states printed by `New-NetIPAddress` are normal: they belong to the active and persistent stores before the address is activated.

### Step 3: Installer Image
Download Ubuntu Server 26.04.1 LTS (live server, amd64) into `C:\HyperV\ISO` and verify the checksum against the `SHA256SUMS` file published next to the image:

```powershell
Get-FileHash C:\HyperV\ISO\ubuntu-26.04.1-live-server-amd64.iso -Algorithm SHA256
```

### Step 4: Create the `mgmt` VM
```powershell
New-VM -Name mgmt -Generation 2 -MemoryStartupBytes 2GB -NewVHDPath C:\HyperV\Disks\mgmt.vhdx -NewVHDSizeBytes 30GB -SwitchName lab-switch
Set-VMProcessor -VMName mgmt -Count 2
Set-VMMemory -VMName mgmt -DynamicMemoryEnabled $false
Set-VMFirmware -VMName mgmt -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
Set-VM -Name mgmt -CheckpointType Disabled
Add-VMDvdDrive -VMName mgmt -Path C:\HyperV\ISO\ubuntu-26.04.1-live-server-amd64.iso
Set-VMFirmware -VMName mgmt -FirstBootDevice (Get-VMDvdDrive -VMName mgmt)
```

| Setting | Value | Reason |
|---|---|---|
| Generation | 2 | UEFI, Secure Boot |
| Secure Boot template | `MicrosoftUEFICertificateAuthority` | The default Windows template does not boot Linux |
| Memory | 2 GiB, static | Predictable resources |
| vCPU | 2 | |
| Disk | 30 GB, dynamically expanding | Grows on demand |
| Checkpoints | Disabled | Avoid accidental rollbacks of long-lived VMs |

### Step 5: Install Ubuntu Server
Start the VM and open its console:

```powershell
Start-VM mgmt
vmconnect.exe localhost mgmt
```

Installer choices:

| Screen | Choice |
|---|---|
| Installation type | Ubuntu Server (not minimized) |
| Network | IPv4 manual: subnet `192.168.50.0/24`, address `192.168.50.20`, gateway `192.168.50.1`, DNS `1.1.1.1,8.8.8.8` |
| Storage | Entire disk, LVM disabled |
| Server name | `mgmt` |
| SSH | Install OpenSSH server |
| Extra packages | None |

After the installation, detach the ISO:

```powershell
Set-VMDvdDrive -VMName mgmt -Path $null
```

### Step 6: Verify the Network from the VM
```bash
ip -br addr
ping -c 2 192.168.50.1
ping -c 2 1.1.1.1
curl -sI https://archive.ubuntu.com | head -n 1
```

### Step 7: Entry Point from Host 1
Create the port mapping and the firewall rule on Host 2:

```powershell
Add-NetNatStaticMapping -NatName lab-nat -Protocol TCP -ExternalIPAddress 0.0.0.0 -ExternalPort 2222 -InternalIPAddress 192.168.50.20 -InternalPort 22
New-NetFirewallRule -DisplayName "lab-mgmt-ssh-in" -Direction Inbound -Protocol TCP -LocalPort 2222 -RemoteAddress <host-1-address> -Action Allow
Get-NetNatStaticMapping
```

Connect from Host 1 to the address of Host 2 on port 2222:

```bash
ssh -p 2222 <user>@<host-2-address>
```

Traffic path:

```text
Host 1 --> Host 2 :2222 --(static NAT mapping)--> mgmt 192.168.50.20 :22
```

SSH authentication hardening is documented separately.

## Results

| Check | Outcome |
|---|---|
| `lab-switch` | Created, type Internal |
| Gateway address on Host 2 | `192.168.50.1/24`, state `Preferred` |
| NAT `lab-nat` | Active on `192.168.50.0/24` |
| `mgmt` address | `eth0` is `192.168.50.20/24` |
| Ping to the internet (`1.1.1.1`) | Works, about 42 ms |
| HTTPS to `archive.ubuntu.com` | Works, so DNS and NAT are functional |
| Ping to the gateway (`192.168.50.1`) | No reply (see below) |
| Port mapping `2222` to `mgmt:22` | Active; login from Host 1 reaches `mgmt` |
| Source address seen on `mgmt` | The real address of Host 1 |

The missing reply to the gateway ping is expected: Windows Firewall blocks inbound ICMP on the new adapter by default. Traffic through NAT is not affected. An optional rule allows it:

```powershell
New-NetFirewallRule -DisplayName "lab-icmp-in" -Protocol ICMPv4 -IcmpType 8 -InterfaceAlias "vEthernet (lab-switch)" -Action Allow
```

## Limitations
- The behavior of lab traffic with a VPN client enabled on Host 2 was not tested.
- The port mapping and the firewall rule depend on the fixed address of Host 2, which is reserved on the home router.
- All steps were performed by hand; codifying them is planned.

## Rollback
```powershell
Remove-NetFirewallRule -DisplayName "lab-mgmt-ssh-in"
Remove-NetNatStaticMapping -NatName lab-nat -StaticMappingID 0
Stop-VM -Name mgmt -TurnOff
Remove-VM -Name mgmt -Force
Remove-Item C:\HyperV\Disks\mgmt.vhdx
Remove-NetNat -Name lab-nat
Remove-VMSwitch -Name lab-switch
```

## Lessons Learned
- **Inventory before changing anything:** a read-only look at switches, NAT, adapters and disks showed that the `Default Switch` was unsuitable and corrected an assumption about the disk.
- **Do not rely on the default switch for fixed addressing:** a dedicated switch with its own subnet and NAT gives stable addresses.
- **One controlled entry point:** a single port mapping plus a source-restricted firewall rule is simpler to reason about than routing a whole subnet.
- **A failed ping is not always a broken network:** the default firewall blocks ICMP, so verify with the traffic that matters (DNS, HTTPS through NAT).
- **Use the Linux Secure Boot template for Linux guests:** the default Windows template prevents the installer from starting.
- **Every manual step is a candidate for code:** this document is the specification for the script and Infrastructure as Code that will replace it.

## Related Documents
- [`03-ollama-setup.md`](03-ollama-setup.md): local LLM setup on Host 1
- [`06-project-direction-change.md`](06-project-direction-change.md): project direction and roadmap
