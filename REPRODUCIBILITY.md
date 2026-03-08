# Reproducibility And Versions

This repository preserves the experiment framework and the curated summaries used for the project. It should reproduce the workflow and the qualitative results, but not necessarily the exact historical runs packet-for-packet.

> A fresh clone should reproduce the experiment pipeline and the qualitative findings, but exact packet counts, contacted domains, software versions, and timing windows may differ due to mutable container tags, upstream application updates, and host-environment differences.

## What Is In This Repo

- Docker Compose configurations for the studied applications
- capture, analysis, and comparison scripts
- curated summary outputs for the automated stack runs and final opt-out reruns
- notes that explain how the public summaries fit together

## What Is Not In This Repo

- the full raw pcap archive from the original study
- the full raw container-log archive from the original study
- exact historical image digests for every measured run

In other words, this snapshot is better suited to reproducing the method than to replaying the original evidence archive exactly.

## Why Reruns May Differ

Several Compose files in this repo use mutable image tags such as `latest` and `release`, including:

- `n8nio/n8n:latest`
- `nextcloud:latest`
- `ghcr.io/immich-app/immich-server:release`
- `ghcr.io/immich-app/immich-machine-learning:release`
- `coredns/coredns:latest`

Those tags can drift over time, which means later pulls may change contacted domains, packet counts, boot timing, and runtime versions even when the scripts stay the same.

## Versions Recovered From The Saved Artifacts

These are the recovered versions for the final automated comparison dataset:

- Docker `29.2.1`
- n8n `2.8.3`
- Immich `v2.5.6`
- Nextcloud `32.0.6.1`
- Redis `7.4.7`
- PostgreSQL `16.12`
- Valkey `9.0.2`

## Drift Seen In Later 72-Hour Captures

The later 72-hour manual captures already showed drift from the same mutable tags:

- n8n `2.9.4`
- Redis `7.4.8`
- PostgreSQL `16.13`
- Valkey `9.0.3`
- Nextcloud runtime drifted as well

That is why the qualitative findings are easier to reproduce than the exact historical counts and version strings.

## If You Want Tighter Reproducibility

- pin image versions or digests in the Compose files
- record image digests in run metadata
- publish a separate artifact manifest if raw evidence is distributed later
