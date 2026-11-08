# Restoring the Windows Boot Entry in systemd-boot

## Goal
Make the systemd-boot menu on Host 1 offer both operating systems after installing Pop!_OS next to Windows 11, without modifying the Windows installation.

Symptom: the menu showed only `Pop!_OS` and `Reboot Into Firmware Interface`. Windows itself was healthy: choosing `Windows Boot Manager` in the BIOS/UEFI boot menu started it normally.

## Environment

| Item | Value |
|---|---|
| Host | Host 1 (dual boot) |
| Bootloader | systemd-boot (Pop!_OS 24.04 LTS) |
| Windows ESP | `/dev/nvme0n1p1`, 200 MiB, vfat |
| Pop!_OS ESP | `/dev/nvme0n1p5`, 1 GiB, vfat, mounted at `/boot/efi` |

## Diagnosis
1. `sudo efibootmgr -v` showed a `Windows Boot Manager` entry in NVRAM pointing to `\EFI\Microsoft\Boot\bootmgfw.efi` on the Windows ESP, plus entries for Pop!_OS and a generic `UEFI OS`.
2. `lsblk` showed that Windows and Pop!_OS use **separate ESPs** (`nvme0n1p1` and `nvme0n1p5`).
3. Mounting the Windows ESP at `/mnt/efi-win` confirmed that `bootmgfw.efi` exists there.
4. An earlier attempt used a bind-mount from `/etc/fstab`. It was broken: the mount point ended up backed by the root partition instead of the Windows ESP, so it did not help.

**Root cause:** systemd-boot detects Windows automatically only if `EFI/Microsoft/Boot/bootmgfw.efi` is located on the **same ESP** as systemd-boot itself. On the Pop!_OS ESP that file did not exist.

## Solution
Copy the Windows bootloader folder onto the Pop!_OS ESP. The Windows ESP is only read, never modified.

### Step 1: Clean Up Previous Attempts
Remove the bind-mount line from `/etc/fstab`, unmount it if it is still active, and reload systemd:

```bash
sudo nano /etc/fstab
sudo umount /boot/efi/EFI/Microsoft
sudo systemctl daemon-reload
```

If `umount` reports that nothing is mounted, continue with the next step.

### Step 2: Copy the Windows Bootloader

```bash
sudo mkdir -p /mnt/efi-win
sudo mount /dev/nvme0n1p1 /mnt/efi-win
ls /mnt/efi-win/EFI/Microsoft/Boot/bootmgfw.efi
sudo cp -r /mnt/efi-win/EFI/Microsoft /boot/efi/EFI/
sudo umount /mnt/efi-win
```

### Step 3: Verify Detection

```bash
sudo ls /boot/efi/EFI/
sudo bootctl list
```

`bootctl list` must show a Windows entry whose EFI path points to `bootmgfw.efi`.

### Step 4: Remove the Duplicate Manual Entry
**Problem:** a manually created `windows.conf` (added earlier as a workaround) produced two Windows entries in the menu: `Windows 11 (windows.conf)` and `Windows 11 (auto-windows)`.

**Cause:** once `bootmgfw.efi` was present on the Pop!_OS ESP, systemd-boot created the `auto-windows` entry on its own, so the manual file became redundant.

**Solution:**

```bash
sudo rm /boot/efi/loader/entries/windows.conf
sudo bootctl list
```

`bootctl list` may still show `windows.conf (reported/absent)`. This is a leftover record in the UEFI variable `LoaderEntries`, purely cosmetic, and is expected to disappear after a reboot.

### Step 5: Set the Default Entry and Timeout

```bash
sudo bootctl set-default Pop_OS-current.conf
sudo bootctl set-timeout 5
```

## Result

| Check | Outcome |
|---|---|
| Boot menu entries | Pop!_OS, Windows Boot Manager (`auto-windows`), Reboot Into Firmware Interface |
| Default entry | `Pop_OS-current.conf` |
| Menu timeout | 5 seconds |
| Windows boot via systemd-boot | Works |
| Windows boot via firmware menu | Unchanged, works |

## Maintenance
The copy on the Pop!_OS ESP is static. Windows updates modify only its own ESP, so after a Windows bootloader update repeat Step 2 to refresh the copy.

## Lessons Learned
- **Do not bind-mount bootloaders blindly:** bind-mounts suit data directories, but copying files onto the ESP is more robust for systemd-boot.
- **Verify with `bootctl list`:** it shows exactly what systemd-boot sees. If an entry is not listed there, it will not boot.
- **Know the auto-detection condition:** it works only when `EFI/Microsoft/Boot/bootmgfw.efi` is on the same ESP as systemd-boot. With that in place, manual `.conf` files are unnecessary and cause duplicates.
- **Check the partition layout first:** `lsblk` and `efibootmgr -v` identified the real problem in minutes and showed that no Windows data was at risk.
- **Read the mount state before acting:** the broken bind-mount was visible in `lsblk` and `findmnt` before any further changes were made.

## Related Documents
- [`01-popos-installation.md`](01-popos-installation.md): installation and partition layout
- [`03-ollama-setup.md`](03-ollama-setup.md): local LLM setup on Host 1
