# Mind Your Stack

**CS/ECE 578 Cyber-Security, Winter 2026, Oregon State University**

Measuring outbound network behavior in self-hosted Docker applications to determine whether periodic telemetry patterns can be used for passive software fingerprinting.

## Research Question

> Is it possible for a passive adversary to fingerprint container software deployments by observing network traffic?

## Key Findings

| App | Telemetry Pattern | Fingerprint Window |
|-----|-------------------|-------------------|
| n8n | Hourly (71/72 hours) | 1 hour |
| Immich | Every 2 hours (odd hours) | 4 hours |
| Nextcloud | ~24 hour interval | 24 hours |

- **DockerGym comparison:** 2-minute observation captures 0% of periodic patterns we observed over 72 hours
- **Opt-out effectiveness:** 100% for all tested applications

## Repository Structure

```
├── scripts/           # Automation and analysis
├── experiments/       # Docker Compose configurations
│   ├── n8n-single/           # n8n with SQLite (baseline)
│   ├── n8n-queue/            # n8n with PostgreSQL + Redis + worker
│   ├── immich/               # Full Immich stack
│   ├── immich-solo/          # Immich server only
│   ├── nextcloud/            # Full Nextcloud stack
│   ├── nextcloud-solo/       # Nextcloud with SQLite
│   ├── n8n-queue-optout-*/   # Opt-out experiments
│   └── nextcloud-optout/     # Opt-out experiment
├── infra/             # CoreDNS instrumentation
└── data/summary/      # Experiment results
```

## Scripts

| Script | Description |
|--------|-------------|
| `run-all.sh` | Runs all 9 experiments sequentially |
| `run-experiment.sh` | Single experiment orchestrator (boot/idle/interact) |
| `run-manual-capture.sh` | Extended multi-hour capture |
| `analyze-experiment.sh` | Background pcap and DNS analysis |
| `analyze-pcap.sh` | Extract DNS, TLS SNI, IPs from pcaps |
| `auto-interact.py` | Playwright browser automation |
| `compare-experiments.sh` | Diff two experiment runs |

## Requirements

- Docker and Docker Compose
- tcpdump, tshark, dig, jq
- Python 3 with Playwright (for interaction phase)
- Root access (for packet capture)

## Setup

```bash
# Install system dependencies
sudo apt install -y tcpdump tshark dnsutils jq

# Install Playwright for browser automation
pip install playwright
playwright install --with-deps chromium
```

## Usage

```bash
# Start DNS instrumentation
cd infra && docker compose up -d

# Run all experiments (default: 3 min boot, 60 min idle, 10 min interaction)
sudo ./scripts/run-all.sh

# Or run a single experiment
sudo ./scripts/run-experiment.sh n8n-single

# Override phase durations (seconds)
sudo MYS_BOOT=60 MYS_IDLE=120 MYS_INTERACT=60 ./scripts/run-all.sh
```

## Related Work

- DockerGym (RAID 2025): "Uncontained Danger: Quantifying Remote Dependencies in Containerized Applications"
- BehavIoT (IMC 2023): "Measuring Smart Home IoT Behavior Using Network-Inferred Behavior Models"
- FingerprinTV (PoPETS 2022): "Fingerprinting Smart TV Apps"

## Authors

- Clarson, Ryan Walker (clarsonr)
- Gujjalapudi Madhusudan, Jisnu (gujjalaj)

## AI Disclosure

This project used Claude (Anthropic) for assistance with shell script development, crash diagnosis, and research outlining. Gemini Deep Research assisted with literature survey.
