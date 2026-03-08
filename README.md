# Mind Your Stack

**CS/ECE 578 Cyber-Security, Winter 2026, Oregon State University**

Mind Your Stack is a three-application case study on whether a passive adversary can fingerprint container software deployments from network traffic alone.

## Research Question

> Is it possible for a passive adversary to fingerprint container software deployments by observing network traffic?

## Scope

This repository is the public code and summary repo for a three-application case study covering n8n, Immich, and Nextcloud. The project asks whether passive fingerprinting is possible in realistic deployments for these applications; it is not intended as a survey of the broader self-hosted ecosystem.

## Datasets

The project draws on four separate datasets:

1. DockerGym baseline: 2-minute isolated image runs used as the short-window comparison point.
2. Automated stack runs: boot, idle, and interaction captures for realistic solo and full-stack deployments.
3. 72-hour manual capture: the separate dataset used for periodicity and fingerprint-window claims.
4. Opt-out reruns: the final reruns used to evaluate telemetry suppression in the tested opt-out variants.

For the public repo, the main references are:

- [Automated stack and opt-out TLS summary](data/summary/all-domains-summary.md)
- [72-hour manual-capture dataset note](MANUAL_CAPTURE_DATASET_NOTE.md)
- [Reproducibility and versions](REPRODUCIBILITY.md)

## Reading The Results

Throughout the summaries, TLS SNI is the main basis for external-destination claims. DNS logs are still useful context, but they are less reliable for per-experiment domain counts because CoreDNS logs can accumulate across runs.

## Results At A Glance

In the automated comparison dataset, DockerGym's 2-minute baseline observed `0` TLS SNI domains across the tested baseline images, while the corresponding full-stack comparison observed `12`. Within this case study, that is evidence that short isolated runs can miss destinations that appear once the applications are deployed in more realistic stacks.

The three applications are useful for different reasons. For n8n, the clearest result is recurring telemetry timing rather than a solo-versus-stack domain gap. For Immich, the clearest result is the difference between the crashing solo setup and the full stack reaching `api.github.com`. For Nextcloud, the strongest orchestration result is the `+3` boot-phase stack-only domains.

The periodicity and fingerprint-window claims come from the separate 72-hour manual-capture dataset. In the archived manual-capture materials, the observed fingerprint windows were `1 hour` for n8n, `4 hours` for Immich, and `24 hours` for Nextcloud. That dataset also has its own total of `10` unique TLS domains, which should be read separately from the automated comparison total of `12`.

For the tested opt-out variants, the final reruns in the curated summary showed `0` remaining TLS SNI domains.

## Reproducibility

A fresh clone should reproduce the experiment pipeline and the qualitative findings, but exact packet counts, contacted domains, software versions, and timing windows may differ over time. Several Compose files use mutable tags, and the public Git repo does not include the full raw pcap and log archive from the original study. [REPRODUCIBILITY.md](REPRODUCIBILITY.md) summarizes the recovered versions for the final automated comparison dataset and the drift already visible in the later 72-hour captures.

## Versions Used In Analysis

Recovered from the saved artifacts for the final automated comparison dataset:

- Docker `29.2.1`
- n8n `2.8.3`
- Immich `v2.5.6`
- Nextcloud `32.0.6.1`
- Redis `7.4.7`
- PostgreSQL `16.12`
- Valkey `9.0.2`

Later 72-hour manual captures already showed drift from the same mutable tags, including n8n `2.9.4`, Redis `7.4.8`, PostgreSQL `16.13`, Valkey `9.0.3`, and additional Nextcloud runtime drift.

## Repository Structure

```text
├── scripts/                 # Automation, analysis, and manual-capture helpers
├── experiments/             # Docker Compose configurations for the studied apps
├── infra/                   # CoreDNS instrumentation
├── data/summary/            # Curated automated-comparison and opt-out summaries
├── MANUAL_CAPTURE_DATASET_NOTE.md  # Separate 72-hour dataset scope and caveats
└── REPRODUCIBILITY.md       # Version recovery and reproducibility caveats
```

## Requirements

- Docker and Docker Compose
- `tcpdump`, `tshark`, `dig`, `jq`
- Python 3 with Playwright for automated interaction
- Root access for packet capture

## Setup

```bash
sudo apt install -y tcpdump tshark dnsutils jq
pip install playwright
playwright install --with-deps chromium
```

## Usage

```bash
# Start DNS instrumentation
cd infra && docker compose up -d

# Run all automated experiments with the current script defaults:
# boot 180s, idle 3600s, interaction 600s
sudo bash scripts/run-all.sh

# Run one experiment
sudo bash scripts/run-experiment.sh n8n-single

# Override phase durations
sudo MYS_BOOT=60 MYS_IDLE=120 MYS_INTERACT=60 bash scripts/run-all.sh

# Start a 72-hour manual capture dataset collection
sudo bash scripts/run-manual-capture.sh nextcloud 72
```

## Related Work

- DockerGym (RAID 2025): "Uncontained Danger: Quantifying Remote Dependencies in Containerized Applications"
- BehavIoT (IMC 2023): "Measuring Smart Home IoT Behavior Using Network-Inferred Behavior Models"
- FingerprinTV (PoPETS 2022): "Fingerprinting Smart TV Apps"

## Authors

- Clarson, Ryan Walker (`clarsonr`)
- Gujjalapudi Madhusudan, Jisnu (`gujjalaj`)

## AI Disclosure

This project used Claude (Anthropic) for assistance with shell script development, crash diagnosis, and research outlining. Gemini Deep Research assisted with literature survey.
