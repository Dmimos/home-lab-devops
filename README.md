# Home Lab: Local Environment for DevOps and AI Agent

## 🎯 Project Goal
Building an isolated home lab to practice DevOps skills, run local LLMs (Large Language Models), and develop an autonomous AI agent. The entire process is documented to build a professional portfolio.

## 🖥️ Architecture and Hardware
The lab consists of two physical hosts:
*   **Host 1:** Ryzen 7 7500, 32GB RAM, RTX 5070 (12GB), 1TB NVMe SSD.
    *   *OS:* Pop!_OS 24.04 LTS (with NVIDIA drivers) + Windows 11 (Dual-Boot).
    *   *Role:* Running local LLM (Ollama), AI agent operations, coding, and lab management.
*   **Host 2:** Windows 11 + Hyper-V.
    *   *Role:* Target host for deploying Virtual Machines (VMs) created by the AI agent from Host 1 via WinRM/SSH.

## 📂 Repository Structure
*   `docs/` — Detailed documentation (e.g., OS installation, troubleshooting).
*   `scripts/` — Automation scripts (e.g., Bash scripts for Linux setup).
*   `configs/` — Configuration files for various tools.

## 🚀 Key Implementations
- **Automated Disk Partitioning:** Developed a Bash script using `parted` to automatically create EFI, Swap, Root, and Home partitions for Pop!_OS, overcoming alignment issues.
- **Secure File Transfer:** Configured SSH/SCP to transfer scripts between Windows and the Pop!_OS Live environment after failing with `git daemon` and NTFS USB drives.
- **Custom OS Installation:** Successfully installed Pop!_OS in Advanced mode without affecting the existing Windows partition.

## 🗺️ Roadmap
- [x] Initial Host configuration and OS installation.
- [ ] Implement Ansible for automated configuration management.
- [ ] Deploy local AI agent for infrastructure automation.
- [ ] Integrate CI/CD pipelines (GitHub Actions) for script validation.

---
*Maintained by [Dmimos](https://github.com/Dmimos)*