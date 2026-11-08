# Pop!_OS Installation Alongside Windows 11 on Host 1

## Goal
Install Pop!_OS 24.04 LTS (NVIDIA edition) next to the existing Windows 11 on Host 1 with these constraints:

- Existing Windows data and partitions stay untouched.
- The partition layout is created by a script, so it is reproducible and free of manual GUI errors.
- Linux gets its own EFI System Partition (ESP), root and home partitions.

## Environment

| Item | Value |
|---|---|
| Host | Host 1 |
| CPU | Ryzen 7 7500 |
| RAM | 32 GB |
| GPU | NVIDIA GeForce RTX 5070, 12 GB VRAM |
| Storage | 1 TB NVMe SSD |
| Existing OS | Windows 11 |
| New OS | Pop!_OS 24.04 LTS (NVIDIA) |
| Install media | Ventoy USB drive (normal mode, Secure Boot disabled in BIOS) |
| Helper machine | Host 2 (Windows 11), used to transfer the script |

## Target Layout

| Mount point | Size | Filesystem | Purpose |
|---|---|---|---|
| `/boot/efi` | 1 GiB | FAT32 | Bootloader (separate from the Windows ESP) |
| swap | 32 GiB | linux-swap | Sized to match RAM, intended for hibernation |
| `/` | 100 GiB | ext4 | System, Docker |
| `/home` | about 319 GiB | ext4 | User data |

The scripted layout is available at [`scripts/linux/create-popos-partitions.sh`](../scripts/linux/create-popos-partitions.sh).

## Step 1: Free Up Disk Space
**Problem:** the built-in Windows 11 Disk Management could not shrink the `C:` volume enough to leave about 450 GiB free.

**Solution:** the volume was shrunk with third-party tools (AOMEI Partition Assistant and GParted). The result was **451.99 GiB** of unallocated space for Linux.

## Step 2: Create the Partitions with a Script
Creating the layout in the installer GUI is error-prone, so the process was automated with a bash script based on `parted`. The partition sizes follow the Target Layout above.

## Step 3: Transfer the Script to Host 1
**Problem:** a second USB drive could not be mounted in the Pop!_OS live environment (NTFS conflict). Serving the file with `git daemon` from Host 2 also failed: Windows Firewall blocked port 9418, and router client isolation was suspected.

**Solution:** install `openssh-server` in the live environment and copy the file with `scp` from Host 2:

```powershell
# Template
scp -o StrictHostKeyChecking=no <path_to_file_on_windows> <username>@<HOST_1_IP>:~/

# Example
scp -o StrictHostKeyChecking=no E:\files\script.sh pop-os@<HOST_1_IP>:~/
```

## Step 4: Fix `parted` Alignment Issues
**Problem:** the first version of the script failed with `The closest location we can manage is...`. Two causes:

1. `parted` aligned partition boundaries automatically and ignored the exact MiB values.
2. The script assumed fixed partition numbers (`p5` to `p8`, since `p1` to `p4` belong to Windows), but interrupted attempts shifted the numbering.

**Solution:** the script was rewritten. It now:

1. Pre-aligns free space to 1 MiB (2048-sector) boundaries.
2. Works strictly with exact sector coordinates.
3. Finds the number of each new partition dynamically (`get_part_num`) by querying `parted` instead of guessing.

## Step 5: Install the Operating System
1. Boot from Ventoy in normal mode and disable Secure Boot in BIOS.
2. Start the Pop!_OS 24.04 LTS (NVIDIA) installer.
3. Select **Custom (Advanced)** mode.
4. Assign the script-created partitions to `/boot/efi`, `/` and `/home`. The swap partition is detected automatically.
5. Leave the existing Windows partitions untouched (formatting unchecked).
6. Click **Erase and Install**. In Custom mode this applies changes only to the partitions selected above.

## Result
Layout of the system disk after installation (`lsblk`):

| Partition | Size | Filesystem | Role |
|---|---|---|---|
| `nvme0n1p1` | 200 MiB | vfat | Windows ESP |
| `nvme0n1p2` | 16 MiB | none | Windows reserved (MSR) |
| `nvme0n1p3` | about 500 GiB | ntfs | Windows system volume (`C:`) |
| `nvme0n1p4` | 900 MiB | ntfs | Windows recovery |
| `nvme0n1p5` | 1 GiB | vfat | Pop!_OS ESP, mounted at `/boot/efi` |
| `nvme0n1p6` | 32 GiB | swap | Mounted as encrypted swap (`/dev/mapper/cryptswap`) |
| `nvme0n1p7` | 100 GiB | ext4 | Root (`/`) |
| `nvme0n1p8` | about 319 GiB | ext4 | `/home` |

Pop!_OS booted successfully. Windows is still bootable from the firmware menu.

## Known Follow-Up
Windows and Pop!_OS use separate ESPs, so the systemd-boot menu initially had no Windows entry. The fix is documented in [`02-windows-boot-fix.md`](02-windows-boot-fix.md).

## Lessons Learned
- **AI output needs verification:** the generated script ran into alignment problems and hardcoded partition numbers. The logic had to be rewritten with explicit alignment and dynamic partition detection.
- **Prefer standard tools over fighting broken ones:** instead of debugging `git daemon` and the firewall, `scp` over SSH solved the file transfer immediately and is the usual approach.
- **Understand what installers hide:** working with `parted` and sector boundaries made the physical structure of a GPT disk concrete.
- **Plan the boot setup up front:** a separate Linux ESP is clean and safe for Windows data, but it needs a follow-up step so the boot menu can see Windows.

## Related Documents
- [`02-windows-boot-fix.md`](02-windows-boot-fix.md): restoring the Windows entry in systemd-boot
- [`03-ollama-setup.md`](03-ollama-setup.md): local LLM setup on Host 1
