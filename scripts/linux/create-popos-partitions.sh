```bash
#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Script must be run as root (sudo)." >&2
    exit 1
fi

# IMPORTANT: Specify your target disk here (check with lsblk)
DISK="/dev/nvme0n1" 

ALIGN=2048   # 1 MiB in 512-byte sectors

# Sizes in sectors (all multiples of 2048)
EFI_SIZE=2097152        # 1 GiB
SWAP_SIZE=67108864      # 32 GiB
ROOT_SIZE=209715200     # 100 GiB
MIN_HOME_SIZE=2097152   # minimum 1 GiB for /home

echo "============================================================"
echo " Target disk: $DISK"
echo " The script will create partitions in exact sectors (1 MiB alignment)."
echo "============================================================"

# Find the largest free space (in sectors)
LARGEST_FREE=$(parted -s -m "$DISK" unit s print free 2>/dev/null \
    | grep ':free;' | sed 's/s//g' \
    | awk -F':' '{print $2" "$3" "$4}' \
    | sort -k3 -nr | head -n 1)

if [ -z "$LARGEST_FREE" ]; then
    echo "Error: could not find free space on $DISK." >&2
    exit 1
fi

FREE_START=$(echo "$LARGEST_FREE" | awk '{print $1}')
FREE_END=$(echo "$LARGEST_FREE" | awk '{print $2}')

# Align start up, and end down to 1 MiB boundary
FREE_START=$(( (FREE_START + ALIGN - 1) / ALIGN * ALIGN ))
FREE_END=$(( (FREE_END + 1) / ALIGN * ALIGN - 1 ))
FREE_SIZE=$(( FREE_END - FREE_START + 1 ))

echo "Free space after alignment: ${FREE_START}s -> ${FREE_END}s (${FREE_SIZE} sectors)."

NEEDED=$(( EFI_SIZE + SWAP_SIZE + ROOT_SIZE + MIN_HOME_SIZE ))
if [ "$FREE_SIZE" -lt "$NEEDED" ]; then
    echo "Error: not enough free space (minimum ${NEEDED} sectors required)." >&2
    exit 1
fi

# Partition end is inclusive: start + size - 1,
# next partition starts at end + 1
EFI_START=$FREE_START
EFI_END=$((EFI_START + EFI_SIZE - 1))

SWAP_START=$((EFI_END + 1))
SWAP_END=$((SWAP_START + SWAP_SIZE - 1))

ROOT_START=$((SWAP_END + 1))
ROOT_END=$((ROOT_START + ROOT_SIZE - 1))

HOME_START=$((ROOT_END + 1))
HOME_END=$FREE_END

echo "------------------------------------------------------------"
echo "The following partitions will be created (in sectors):"
echo "  EFI  (1GB)  : ${EFI_START} -> ${EFI_END}"
echo "  Swap (32GB) : ${SWAP_START} -> ${SWAP_END}"
echo "  Root (100GB): ${ROOT_START} -> ${ROOT_END}"
echo "  Home (rest) : ${HOME_START} -> ${HOME_END}"
echo "------------------------------------------------------------"

read -r -p "Continue creating partitions? Enter YES to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Cancelled."
    exit 1
fi

# Returns the partition number that starts at the given sector
get_part_num() {
    local start="$1"
    parted -s -m "$DISK" unit s print 2>/dev/null \
        | grep -E '^[0-9]+:' \
        | awk -F':' -v s="${start}s" '$2 == s {print $1}' \
        | head -n 1
}

create_part() {
    local name="$1" fs="$2" start="$3" end="$4"
    parted -s -a optimal "$DISK" mkpart "$name" "$fs" "${start}s" "${end}s"
    partprobe "$DISK"
    sleep 1
    local num
    num=$(get_part_num "$start")
    if [ -z "$num" ]; then
        echo "Error: failed to determine partition number for $name." >&2
        exit 1
    fi
    echo "$num"
}

echo "Creating partitions..."

EFI_NUM=$(create_part EFI fat32 "$EFI_START" "$EFI_END")
parted -s "$DISK" set "$EFI_NUM" esp on
SWAP_NUM=$(create_part swap linux-swap "$SWAP_START" "$SWAP_END")
ROOT_NUM=$(create_part root ext4 "$ROOT_START" "$ROOT_END")
HOME_NUM=$(create_part home ext4 "$HOME_START" "$HOME_END")

partprobe "$DISK"
sleep 2

EFI_DEV="${DISK}p${EFI_NUM}"
SWAP_DEV="${DISK}p${SWAP_NUM}"
ROOT_DEV="${DISK}p${ROOT_NUM}"
HOME_DEV="${DISK}p${HOME_NUM}"

echo "Formatting partitions..."

mkfs.fat -F32 -n EFI "$EFI_DEV"
mkswap -L swap "$SWAP_DEV"
mkfs.ext4 -L root "$ROOT_DEV"
mkfs.ext4 -L home "$HOME_DEV"

echo
echo "============================================================"
echo " Done! Partitions created and formatted:"
echo "   $EFI_DEV -> EFI  (fat32, label EFI)"
echo "   $SWAP_DEV -> swap (linux-swap 32GB, label swap)"
echo "   $ROOT_DEV -> root (ext4, label root)"
echo "   $HOME_DEV -> home (ext4, label home)"
echo "============================================================"