# Swap Optimization on Host 1

## Goal
Right-size the disk swap on Host 1 after sleep and hibernation were dropped, without putting existing data at risk.

## Context
- During installation a 32 GiB swap partition was created, sized to match RAM so that hibernation would be possible.
- Remote wake-up was abandoned (see [`04-wowlan-investigation.md`](04-wowlan-investigation.md)), and Host 1 is now powered on only while the local AI assistant is working. Sleep and hibernation are no longer used.
- The target lab infrastructure runs on Host 2, so Host 1 does not need a large memory safety net.

## Measurements Before the Change

| Item | Value |
|---|---|
| RAM | 30 GiB total, about 26 GiB available |
| zram | 16 GiB, zstd, priority 1000, 4 KiB of data stored |
| Disk swap | 32 GiB (`/dev/mapper/cryptswap`), priority -1, 0 B used |
| Root (`/`) | 21 GiB used of 98 GiB (22%) |
| `/home` | 702 MiB used of 313 GiB (1%) |

The values were taken on an idle system; no load test was run.

The swap is configured in `/etc/crypttab` with a random key from `/dev/urandom` in plain mode. Its content is discarded at every boot, so hibernation could never have worked with this swap. Because zram has the higher priority, the disk swap is only used after the 16 GiB of zram is full.

## Options

| Option | What happens | Risk | Verdict |
|---|---|---|---|
| A | Shrink the swap partition to 8 GiB and leave the freed 24 GiB unallocated | Low: no data moves, only the end of one partition changes | Chosen |
| B | Shrink swap, move the root partition left from a live USB, then extend `/home` | Medium: moving the root partition is an offline operation and a power loss in the middle can destroy the system | Rejected |

Why B was rejected:

- The freed space sits between the swap and root partitions, while `/home` is behind the root partition, so it cannot be extended directly.
- The gain is 24 GiB on top of 319 GiB, while `/home` is 1% used.
- It is a manual graphical operation that cannot be expressed as code or reviewed.

## Decision
Shrink the swap partition from 32 GiB to 8 GiB and keep 24 GiB unallocated for future needs. Total swap becomes 8 GiB on disk plus 16 GiB of zram, which `free -h` reports as 23 GiB instead of 47 GiB.

| Partition 6 | Start (MiB) | End (MiB) | Size (MiB) |
|---|---|---|---|
| Before | 514046 | 546814 | 32768 |
| After | 514046 | 522238 | 8192 |
| Unallocated | 522238 | 546814 | 24576 |

Partitions 7 and 8 keep their positions, and the start of partition 6 does not change, so the UUID referenced in `/etc/crypttab` stays valid and neither `crypttab` nor `fstab` needs editing.

## Procedure

### Step 1: Back Up the Configuration

```bash
B=~/backups/pre-swap-changes
mkdir -p $B
sudo cp -a /etc/fstab /etc/crypttab $B/
sudo sfdisk -d /dev/nvme0n1 > $B/nvme0n1-partition-table.sfdisk
```

The partition table dump contains partition identifiers, so it is kept outside the repository. A copy was also stored on another machine and checked to contain all eight partitions.

### Step 2: Disable the Swap

```bash
sudo swapoff /dev/mapper/cryptswap
sudo cryptsetup close cryptswap
swapon --show
```

Only `zram0` must remain in the output.

### Step 3: Shrink the Partition

```bash
sudo parted /dev/nvme0n1 unit MiB resizepart 6 522238MiB
```

Parted warns about data loss when shrinking. The warning is irrelevant here because the swap content is discarded at every boot.

### Step 4: Verify the Partition Table

```bash
sudo parted /dev/nvme0n1 unit MiB print free
```

### Step 5: Reboot and Verify

```bash
sudo reboot
```

After reconnecting:

```bash
swapon --show
free -h
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
systemctl is-active systemd-cryptsetup@cryptswap.service
```

## Results

| Check | Outcome |
|---|---|
| Partition 6 | 8192 MiB, from 514046 to 522238 MiB |
| Unallocated space | 24576 MiB between partitions 6 and 7 |
| Partitions 7 and 8 | Unchanged, same start positions |
| Disk swap after reboot | `/dev/mapper/cryptswap`, 8 GiB, recreated on boot |
| zram | 16 GiB, priority 1000 |
| Total swap reported by `free -h` | 23 GiB (was 47 GiB) |
| `systemd-cryptsetup@cryptswap.service` | active |
| `/etc/crypttab` and `/etc/fstab` | Not modified |

## Rollback
If the swap does not come back, or the change has to be undone, close the swap and restore the original size, then reboot:

```bash
sudo swapoff /dev/mapper/cryptswap
sudo cryptsetup close cryptswap
sudo parted /dev/nvme0n1 unit MiB resizepart 6 546814MiB
```

Restoring the whole partition table from the `sfdisk` dump is the last resort and must be done from a live USB, not on the running system.

## Lessons Learned
- **Measure before sizing:** the 32 GiB swap came from a hibernation requirement that no longer existed, and the measurements showed it was never used.
- **Know what random-key swap implies:** encrypted swap on `/dev/urandom` is safe and simple, but it rules out hibernation. Decide on hibernation before choosing the swap type.
- **Partition order matters:** placing swap between the ESP and the root partition makes growing `/home` expensive. On future systems a swap file or LVM avoids dependence on disk adjacency.
- **Rejecting a risky change is a decision too:** an operation with a small payoff and a real failure mode is not worth doing, and recording the trade-off is more useful than the operation itself.
- **Keep identifiers out of the repository:** partition table dumps contain UUIDs and belong in a backup location, not in version control.
- **Verify after each step:** the partition table, the swap devices and the cryptsetup service were checked separately, and the final check was done after a real reboot.

## Related Documents
- [`01-popos-installation.md`](01-popos-installation.md): original partition layout
- [`04-wowlan-investigation.md`](04-wowlan-investigation.md): why sleep and hibernation were dropped
