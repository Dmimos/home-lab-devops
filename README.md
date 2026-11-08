# Home Lab: DevOps Practice Environment with a Local AI Assistant

## Goal
Build an isolated home lab to practice DevOps skills: PostgreSQL replication and backup, configuration management, monitoring and CI/CD. A local LLM assists with routine work. Everything is documented as a professional portfolio.

## Design Principles
- **Local only:** the LLM runs on Host 1 and no prompts or files are sent to external services.
- **Human in the loop:** the assistant proposes code, configs and documentation; changes are applied through reviewed commits and a pipeline, and destructive operations stay manual.
- **Documented and reproducible:** every step ends up in `docs/`, and automation lives in `scripts/` and `configs/`.
- **English only:** all repository content, including commits and pull requests, is in English.

## Architecture

| Host | Hardware | OS | Role |
|---|---|---|---|
| Host 1 | Ryzen 7 7500, 32 GB RAM, RTX 5070 (12 GB), 1 TB NVMe SSD | Pop!_OS 24.04 LTS (NVIDIA) and Windows 11, dual boot | Local LLM (Ollama), development, lab management |
| Host 2 | Core i7-9700K, 16 GB RAM, 500 GB SSD | Windows 11 Pro with Hyper-V | Hyper-V host for the lab virtual machines |

Planned virtual machines on Host 2 (Ubuntu Server, network `192.168.50.0/24`):

| VM | Address | Role |
|---|---|---|
| `pg1` | `192.168.50.11` | PostgreSQL primary |
| `pg2` | `192.168.50.12` | PostgreSQL streaming standby |
| `mgmt` | `192.168.50.20` | Ansible control node, pgBackRest repository, CI runner |
| `mon` | `192.168.50.30` | Prometheus, Alertmanager, Grafana |

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1. Host 1 foundation | Dual boot of Pop!_OS and Windows 11, scripted disk partitioning, boot menu fix | Done |
| 2. Local LLM runtime | Ollama with `qwen3.5:9b`, GPU tuning, measured results | Done |
| 3. Local assistant | Isolated user and workspace, editing tool connected to Ollama, evaluation against alternative models | Next |
| 4. Lab network and VMs | Hyper-V virtual switch, four Ubuntu Server VMs with static addresses | Planned |
| 5. Configuration management | Ansible baseline on `mgmt`: inventory, roles, secrets handling | Planned |
| 6. PostgreSQL replication | Streaming replication `pg1` to `pg2` with a replication slot, documented manual failover | Planned |
| 7. Backup and recovery | pgBackRest with the repository on `mgmt`, scheduled and automated restore verification | Planned |
| 8. Monitoring | Prometheus, Alertmanager and Grafana with node, PostgreSQL and backup metrics | Planned |
| 9. CI/CD | GitHub Actions with a self-hosted runner, lint and check-mode stages, manual approval for deployments | Planned |

## Key Implementations
- **Automated disk partitioning:** a Bash script based on `parted` creates the EFI, swap, root and home partitions for Pop!_OS, with exact sector alignment and dynamic partition numbering.
- **Non-destructive dual boot:** Pop!_OS installed in Custom mode without touching the existing Windows partitions.
- **Boot menu repair:** the Windows entry was restored in systemd-boot by copying the bootloader to the Linux ESP; the root cause and fix are documented.
- **Local LLM runtime:** Ollama bound to loopback with `qwen3.5:9b` running 100% on the GPU at a 32K context window, about 7.2 GB of 12 GB VRAM in use and roughly 97 tokens per second.

## Documentation

| Document | Content |
|---|---|
| [`01-popos-installation.md`](docs/01-popos-installation.md) | Partition layout, scripted partitioning, OS installation |
| [`02-windows-boot-fix.md`](docs/02-windows-boot-fix.md) | Restoring the Windows entry in systemd-boot |
| [`03-ollama-setup.md`](docs/03-ollama-setup.md) | Ollama and `qwen3.5:9b` setup, tuning and measurements |

## Repository Structure

| Path | Content |
|---|---|
| `docs/` | Step-by-step documentation and troubleshooting notes |
| `scripts/` | Automation scripts (for example `scripts/linux/create-popos-partitions.sh`) |
| `configs/` | Configuration files for lab tools |

---
Maintained by [Dmimos](https://github.com/Dmimos)
