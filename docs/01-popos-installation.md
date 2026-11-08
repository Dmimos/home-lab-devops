# Pop!_OS Installation Process and Challenges

## 🛠️ Step 1: Disk Preparation (Host 1)
**Problem:** Standard Windows 11 tools ("Disk Management") could not shrink the C: volume to the desired size (leaving only ~450 GiB).
**Solution:** Shrinking was performed using third-party software (AOMEI Partition Assistant / GParted). A total of **451.99 GiB** of unallocated space was allocated for the Linux installation.

## 📜 Step 2: Creating the Partition Scheme via Bash Script
To install Pop!_OS, partitions needed to be created considering the 32GB RAM (swap must be at least equal to RAM size for hibernation to work). It was decided to automate the process via a bash script to avoid manual entry errors in the GUI.

**Partition Scheme:**
*   **EFI:** 1 GiB (fat32) — for the bootloader.
*   **Swap:** 32 GiB (linux-swap) — for hibernation.
*   **Root (/):** 100 GiB (ext4) — for the system and Docker.
*   **Home (/home):** ~318 GiB (ext4) — for user data.

The full script can be found at `scripts/linux/create-popos-partitions.sh`.

## 🌐 Step 3: Transferring the Script to Host 1
**Problem:** A Ventoy USB drive was used for the OS installation. However, a secondary USB drive failed to mount in the Pop!_OS Live environment (NTFS conflict). An attempt to transfer the file via `git daemon` from Host 2 (Windows) failed due to Windows Firewall blocking port 9418 and probable router client isolation.

**Solution:** A standard DevOps approach was applied — using SSH and SCP. `openssh-server` was installed on Host 1, and the file was transferred in one command from Host 2:

```powershell
# Command template
scp -o StrictHostKeyChecking=no <path_to_file_on_Windows> <username>@<HOST_1_IP>:~/

# Real command example
scp -o StrictHostKeyChecking=no E:\files\script.sh pop-os@<HOST_1_IP>:~/
```
## ⚙️ Step 4: Overcoming `parted` Alignment Issues
**Problem:** The initial AI-generated script threw an error: `The closest location we can manage is...`. This happened for two reasons:
1. `parted` tried to align partition boundaries automatically, ignoring exact MiB values.
2. The script expected specific partition numbers (e.g., p5-p8, since p1-p4 were occupied by Windows), but interrupted attempts shifted the numbering.

**Solution:** The script was rewritten. It now:
1. Pre-aligns free space to 1 MiB (2048 sectors) boundaries.
2. Works strictly with exact sector coordinates.
3. Dynamically finds the number of the created partition (`get_part_num`) by querying `parted`, rather than guessing.

## 💿 Step 5: OS Installation
1. Booted from Ventoy (Normal Mode). Disabled Secure Boot in BIOS.
2. Started the Pop!_OS 24.04 LTS (NVIDIA) installer.
3. Selected **Custom (Advanced)** mode.
4. Mounted the script-created partitions (EFI, Root, Home) to `/boot/efi`, `/`, and `/home`. The swap partition was detected automatically.
5. **Important:** The existing Windows partition was left untouched (formatting checkbox unchecked).
6. Clicked "Erase and Install" (which in Custom mode only applies changes to the newly selected partitions).

## 🧠 DevOps Insights & Lessons Learned
* **AI is a tool, not absolute truth:** The AI-generated script encountered sector alignment issues and hardcoded partition numbers. An engineering mindset was required to rewrite the logic, add dynamic partition detection, and manual alignment.
* **Don't waste time on broken tools:** Instead of spending hours fixing `git daemon` and fighting Windows Firewall, a standard and secure `scp` was used. This saved time and provided hands-on SSH experience.
* **Understanding sectors:** Graphical installers hide many processes. Using `parted` in the terminal and solving the alignment issue provided a clear understanding of how GPT partition tables physically work.