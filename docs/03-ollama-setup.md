# Local LLM Setup: Ollama with qwen3.5:9b on Host 1

## Goal
Run a local LLM on Host 1 to assist with lab routine: drafting Ansible roles and configs, explaining logs and alerts, writing documentation, and reviewing diffs. Requirements:

- Everything runs locally; no prompts or files leave the machine.
- The Ollama API is reachable only from the host itself.
- The model fits entirely in VRAM, so responses stay fast.
- The model only produces text; applying changes stays a manual step.

## Environment

| Item | Value |
|---|---|
| CPU | Ryzen 7 7500 |
| RAM | 32 GB |
| GPU | NVIDIA GeForce RTX 5070, 12 GB VRAM |
| Storage | 1 TB NVMe SSD |
| OS | Pop!_OS 24.04 LTS (dual boot with Windows 11) |
| NVIDIA driver | 595.84 (CUDA 13.2) |
| Ollama | 0.40.15 |
| Model | `qwen3.5:9b` (about 6.6 GB on disk) |

## Model Choice
Candidates: `qwen3.5:9b`, `gemma4:12b`, `qwen3:8b`, `qwen2.5-coder:14b`.

`qwen3.5:9b` was selected because:

- It leaves the most VRAM headroom for a 32K context window on a 12 GB card.
- It has the most recent training data, which matters for current Postgres, Ansible and pgBackRest options.
- It supports a non-thinking mode, which is better suited to routine tasks.

Known risks: open tool-calling parser issues in Ollama, and a tendency to loop in thinking mode. Mitigation: use plain text and JSON-schema output instead of native tool calling, and keep thinking mode off by default.

## Step 1: Pre-Flight Checks

```bash
nvidia-smi
df -h / /home
```

Results:

- Driver 595.84 recognized the RTX 5070.
- Idle VRAM usage was 213 MiB (desktop compositor only), leaving almost the full 12 GB for the model.
- Free disk space: 83 GB on `/` and 297 GB on `/home`. Model storage did not need to be moved.

## Step 2: Install Ollama
The installer is downloaded and reviewed before running, because it executes as root.

```bash
curl -fsSL https://ollama.com/install.sh -o ollama-install.sh
less ollama-install.sh
sh ollama-install.sh
```

The installer created the `ollama` user, added it to the `render` and `video` groups, created a systemd service, and detected the NVIDIA GPU without touching the existing driver.

Verify that the API listens on the loopback interface only:

```bash
ollama --version
systemctl status ollama --no-pager
ss -ltnp | grep 11434
```

Expected: `127.0.0.1:11434`, not `0.0.0.0:11434`.

## Step 3: Pull the Model and Smoke Test

```bash
ollama pull qwen3.5:9b
ollama run qwen3.5:9b "Name three postgresql.conf parameters that matter for replication."
```

While the model is loaded, check placement in a second terminal:

```bash
ollama ps
nvidia-smi
```

`ollama ps` must show `100% GPU`. Take measurements while the model is loaded; it is unloaded after the keep-alive period.

## Step 4: Service Tuning
Create a systemd drop-in:

```bash
sudo systemctl edit ollama
```

Content (placed between the two marker comments in the editor):

```ini
[Service]
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_CONTEXT_LENGTH=32768"
Environment="OLLAMA_KEEP_ALIVE=30m"
```

Apply and verify:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
systemctl show ollama --property=Environment
```

| Variable | Purpose |
|---|---|
| `OLLAMA_FLASH_ATTENTION=1` | Enables flash attention, required for KV cache quantization |
| `OLLAMA_KV_CACHE_TYPE=q8_0` | Quantizes the KV cache to reduce VRAM use |
| `OLLAMA_CONTEXT_LENGTH=32768` | Default context window (the built-in default was 4096) |
| `OLLAMA_KEEP_ALIVE=30m` | Keeps the model loaded between requests |

## Results

| Metric | Defaults (4K context) | Tuned (32K context) |
|---|---|---|
| Context shown by `ollama ps` | 4096 | 32768 |
| Processor | 100% GPU | 100% GPU |
| Model size in `ollama ps` | 5.6 GB | 6.2 GB |
| `llama-server` VRAM | 6426 MiB | 6962 MiB |
| Total VRAM in use | 6647 MiB of 12227 MiB | 7183 MiB of 12227 MiB |

An eight-fold larger context window cost only about 540 MiB of VRAM, leaving roughly 5 GB free.

Performance in non-thinking mode (`--think=false`, 315 generated tokens):

| Metric | Value |
|---|---|
| Generation speed | 97.5 tokens/s |
| Model load (cold start) | 4.4 s |
| Total duration | 8.4 s |

## Answer Quality Check
The test question was answered correctly in part. Verified against the PostgreSQL documentation:

| Item | Verdict |
|---|---|
| `wal_level` | Correct and central. The model also listed a non-existent value (`logical_decoding`); valid values are `minimal`, `replica` and `logical`. |
| `max_wal_senders` | Correct. |
| `listen_addresses` | Needed for remote standbys, but a networking setting rather than a replication parameter. |
| `max_replication_slots` | Missing, although it is one of the core replication parameters. |
| `pg_hba.conf` remark | Imprecise. What is actually required is a `replication` entry for the standby host. |

Conclusion: the model is useful for drafting and explaining, but it can state wrong details with confidence. Every generated config goes through `ansible-lint`, `--syntax-check`, `--check --diff` and a check against official documentation before it is applied.

## Thinking Mode
With the default 4096-token context and thinking enabled, the model spent its whole budget on reasoning, repeatedly changing its mind about the third parameter, and the captured output contained no final answer. With thinking disabled the same question took 315 tokens and about three seconds.

Operational rule: keep thinking off for routine work (configs, log explanations, JSON output) and enable it only for hard debugging, with the 32K context in place.

```bash
ollama run qwen3.5:9b --think=false --verbose "<prompt>"
```

## Lessons Learned
- Measure only while the model is loaded; `ollama ps` is empty before the first request and after the keep-alive timeout.
- Check the context shown by `ollama ps`. The default of 4096 tokens is too small for repository-sized prompts and for thinking mode.
- Review third-party installers before running them as root, and confirm that the API is bound to loopback.
- Disabling the graphical session would save only about 160 MiB of VRAM, so it was not worth the loss of local console access.

## Next Steps
- Create a dedicated unprivileged user and workspace for the agent.
- Connect an editing tool (for example Aider) to the local endpoint.
- Build a small evaluation set of lab tasks and compare against `gemma4:12b`.
