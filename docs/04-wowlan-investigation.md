# WoWLAN Investigation and Hardware Limitations

## Goal
Enable Wake-on-Wireless LAN (WoWLAN) on Host 1 so that it can be woken from sleep (S3) by a magic packet sent from Host 2.

## Environment

| Item | Value |
|---|---|
| Host | Host 1 |
| Motherboard | ASRock B650 PG Lightning (UEFI 3.50) |
| Wi-Fi module | Intel Wi-Fi 6 AX200 |
| OS | Pop!_OS 24.04 LTS |
| Kernel | 7.2.15-76070215-generic |
| Driver | `iwlwifi` |
| Sender | Host 2, same local network |

## Configuration Attempts

| # | Layer | Change |
|---|---|---|
| 1 | Driver | Verified WoWLAN support and enabled magic packet detection with `iw` |
| 2 | NetworkManager | Persisted the setting on the Wi-Fi connection profile |
| 3 | systemd service | `wowlan.service` re-applies the `iw` settings after boot |
| 4 | systemd sleep hook | `/usr/lib/systemd/system-sleep/wowlan-rearm.sh` re-applies the settings right before sleep |
| 5 | BIOS | Deep Sleep disabled, PCIE Devices Power On enabled, PCIe Power Management Features disabled |
| 6 | Kernel parameters | `iwlmvm.power_scheme=1` and `pcie_port_pm=off`, added with `kernelstub` |

Commands for the first two layers:

```bash
sudo iw phy phy0 wowlan enable magic-packet disconnect
sudo nmcli connection modify "<wifi connection name>" wifi.wake-on-wlan magic
```

Verification of the active configuration:

```bash
sudo iw phy phy0 wowlan show
```

The output confirmed that magic packet detection was active.

## Test Procedure
1. Put Host 1 into sleep (S3).
2. Send a magic packet to the Wi-Fi adapter MAC address from Host 2.
3. Observe whether Host 1 wakes up.

## Result
Host 1 did not wake up on the magic packet, although every layer above was configured and verified. It woke up only with the power button.

## Root Cause Analysis
The kernel log after the manual wake-up contained the decisive message:

```text
iwlwifi 0000:06:00.0: Can't resume, device_powered_off() was called during wowlan
```

Interpretation:

- The driver reports that the Wi-Fi device lost power while it was supposed to listen for the magic packet.
- A card without power cannot receive packets, so no software-side setting can fix this.
- The most likely cause is that the motherboard firmware removes power from the M.2 slot in S3. This was not confirmed by a direct power measurement, but it matches the log and the fact that all software and BIOS options were already exhausted.

Conclusion: this is a hardware or firmware limitation of the platform, not a configuration error.

## Alternatives Considered

| Option | How it works | Notes |
|---|---|---|
| Wired Wake-on-LAN | Magic packet to the Ethernet adapter, which stays powered in standby | Most reliable; requires a cable and `Wake-on` set to `g` on the wired interface |
| Smart plug with firmware restore option | Cut and restore power; BIOS setting `Restore on AC Power Loss = Power On` starts the host | Only wakes a fully powered-off host; never cut power to a running system |
| Scheduled wake | RTC alarm in BIOS or `rtcwake` from Linux | No network needed; suited to planned start times |

## Decision
Remote wake-up was a nice-to-have, not a requirement of the lab. Since the only wireless path is blocked by the hardware and the alternatives would add cabling, extra hardware or scheduling for little benefit, the feature was dropped. Host 1 is started manually when needed.

## Lessons Learned
- **Read the logs first:** the kernel log gave the exact answer and prevented further blind trial and error.
- **Separate configuration problems from hardware limits:** once all layers were verified, the remaining explanation had to be below the operating system.
- **Document failed attempts:** a post-mortem with evidence is as valuable as a working setup and shows the diagnostic method.
- **Weigh effort against value:** stopping work on a nice-to-have feature once its cost clearly exceeds its benefit is a legitimate engineering decision.

## Related Documents
- [`01-popos-installation.md`](01-popos-installation.md): installation and partition layout
- [`02-windows-boot-fix.md`](02-windows-boot-fix.md): systemd-boot and Windows entry
- [`03-ollama-setup.md`](03-ollama-setup.md): local LLM setup on Host 1
