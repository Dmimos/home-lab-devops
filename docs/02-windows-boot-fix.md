# Restoring Windows Boot Entry in systemd-boot

## 🔴 The Problem
After installing Pop!_OS alongside Windows 11, the systemd-boot menu did not have a Windows entry. Only `Pop!_OS` and `Reboot Into Firmware Interface` were shown. Windows itself was fine: selecting `Windows Boot Manager` from the BIOS/UEFI boot menu started it normally.

## 🔍 Diagnosis
1. Checked UEFI boot entries with `sudo efibootmgr -v`. The `Windows Boot Manager` entry was present in NVRAM and pointed to `\EFI\Microsoft\Boot\bootmgfw.efi` on the Windows EFI partition (`/dev/nvme0n1p1`).
2. Checked the partition layout with `lsblk`. Windows and Pop!_OS use **separate ESPs**: `nvme0n1p1` (200M, Windows) and `nvme0n1p5` (1G, Pop!_OS, mounted at `/boot/efi`).
3. Mounted the Windows ESP at `/mnt/efi-win` and confirmed that `bootmgfw.efi` exists there.
4. An earlier attempt with a bind-mount in `/etc/fstab` was broken (the bind-mount ended up pointing at the root partition instead of the Windows ESP) and did not help.

**Root cause:** systemd-boot auto-detects Windows only if `EFI/Microsoft/Boot/bootmgfw.efi` is located on the **same ESP** as systemd-boot itself. On the Pop!_OS ESP that file did not exist.

## 🛠️ The Solution
Copy the Windows bootloader folder onto the Pop!_OS ESP.

### Step 1: Copy the Windows Bootloader
1. Clean up previous attempts: remove the bind-mount line from `/etc/fstab`, unmount it, then run `sudo systemctl daemon-reload`.
2. Mount the Windows ESP and copy the bootloader folder:

```bash
sudo mkdir -p /mnt/efi-win
sudo mount /dev/nvme0n1p1 /mnt/efi-win
sudo cp -r /mnt/efi-win/EFI/Microsoft /boot/efi/EFI/
sudo umount /mnt/efi-win
```

### Step 2: Verify systemd-boot Configuration
Check that systemd-boot recognizes the copied files:

```bash
sudo bootctl list
```

The output shows a Windows entry with the correct EFI path.

### Step 3: Cleanup Duplicate Boot Entries
**Problem:** a manually created `windows.conf` (added earlier as a workaround) resulted in two identical Windows entries in the boot menu: `Windows 11 (windows.conf)` and `Windows 11 (auto-windows)`.

**Cause:** once `bootmgfw.efi` was present on the Pop!_OS ESP, systemd-boot created the `auto-windows` entry by itself, so the manual file became redundant.

**Solution:** remove the manual entry:

```bash
sudo rm /boot/efi/loader/entries/windows.conf
```

`auto-windows` is a cleaner and more robust approach.

**Final verification:** `sudo bootctl list` shows the old `windows.conf` as `(reported/absent)`. This is a leftover record in the UEFI variables (`LoaderEntries`), purely cosmetic, and it disappears after a reboot. `Windows Boot Manager (auto-windows)` is active and works.

### Step 4: Set Default Boot and Timeout

```bash
sudo bootctl set-default Pop_OS-current.conf
sudo bootctl set-timeout 5
```

## 🧠 DevOps Insights
- **Don't bind-mount bootloaders blindly:** bind-mounts are fine for data, but copying files directly onto the ESP is more robust for systemd-boot.
- **Always verify with `bootctl list`:** it shows exactly what systemd-boot sees. If the entry is not listed, it will not boot.
- **Auto-detection has a condition:** it works only if `EFI/Microsoft/Boot/bootmgfw.efi` is on the same ESP as systemd-boot. Manual `.conf` files are then unnecessary and lead to duplicates.
- **Keep the copy up to date:** Windows updates only its own ESP. If the Windows bootloader is updated, repeat Step 1.