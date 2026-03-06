# Mind Your Stack - External Domains Summary

Generated: Wed Feb 19 08:35:00 PM PST 2026
Updated: Wed Feb 26 2026 (added DockerGym baseline comparison)

---

## DockerGym Baseline Comparison (2026-02-26)

**Methodology:** Replicated DockerGym's exact approach (2-min `docker run -dit`, isolated network, tcpdump capture) on our target images.

### TLS Connections: DockerGym vs Full Stack

| Application | DockerGym (2 min) | Full Stack (65 min) | Gap |
|-------------|-------------------|---------------------|-----|
| n8n | 0 | 2 | +2 (100% missed) |
| immich | 0 | 1 | +1 (100% missed) |
| nextcloud | 0 | 9 | +9 (100% missed) |
| **Total** | **0** | **12** | **+12** |

### DockerGym Baseline Details

| Image | DNS Queries | TLS Connections | Notes |
|-------|-------------|-----------------|-------|
| n8nio/n8n | telemetry.n8n.io, posthog | 0 | DNS resolved but TLS not completed |
| altran1502/immich-machine-learning | mDNS only | 0 | Sits idle without server |
| altran1502/immich-proxy | immich-server (failed) | 0 | Looking for missing server |
| altran1502/immich-web | mDNS only | 0 | Sits idle without API |
| nextcloud | mDNS only | 0 | Boot exceeds 2 min |

**Key Finding:** DockerGym's 2-minute window captured **0% of TLS-level external dependencies**.

---

## Domain Purpose Reference

| Domain | Purpose | Essential? | Privacy Concern |
|--------|---------|-----------|-----------------|
| us.i.posthog.com | Product analytics, session recordings | No | High |
| telemetry.n8n.io | Workflow telemetry (node schemas) | No | High |
| enterprise.n8n.io | Enterprise license validation | No | Low |
| license.n8n.io | License key verification | No | Low |
| api.github.com | Version check (GitHub releases API) | No | Medium |
| pushfeed.nextcloud.com | Announcement RSS feed | No | Low |
| garm2.nextcloud.com | App store mirror (CDN) | For updates | Low |
| garm3.nextcloud.com | App store mirror (CDN) | For updates | Low |
| apps.nextcloud.com | App store catalog | For updates | Low |
| updates.nextcloud.com | Software update checks | No | Low |
| www.nextcloud.com | Main website (redirects) | No | Low |
| nextcloud.com | Main domain | No | Low |
| raw.githubusercontent.com | GitHub raw content | No | Low |
| github.com | GitHub links | No | Low |

---

## All External Domains by App and Phase (TLS SNI)

## n8n-single

| Domain | Phase | Count |
|--------|-------|-------|
| us.i.posthog.com | boot | 3 |
| telemetry.n8n.io | boot | 2 |
| us.i.posthog.com | idle | 2 |
| telemetry.n8n.io | idle | 1 |

## n8n-queue

| Domain | Phase | Count |
|--------|-------|-------|
| us.i.posthog.com | boot | 3 |
| telemetry.n8n.io | boot | 2 |
| us.i.posthog.com | idle | 2 |
| telemetry.n8n.io | idle | 1 |

## immich-solo

| Domain | Phase | Count |
|--------|-------|-------|

## immich

| Domain | Phase | Count |
|--------|-------|-------|
| api.github.com | boot | 1 |
| api.github.com | idle | 1 |

## nextcloud-solo

| Domain | Phase | Count |
|--------|-------|-------|
| apps.nextcloud.com | interaction | 4 |
| www.nextcloud.com | interaction | 2 |
| updates.nextcloud.com | interaction | 2 |
| nextcloud.com | interaction | 2 |
| raw.githubusercontent.com | interaction | 1 |
| github.com | interaction | 1 |
| garm3.nextcloud.com | interaction | 1 |

## nextcloud

| Domain | Phase | Count |
|--------|-------|-------|
| pushfeed.nextcloud.com | boot | 2 |
| garm3.nextcloud.com | boot | 1 |
| apps.nextcloud.com | boot | 1 |
| apps.nextcloud.com | interaction | 4 |
| www.nextcloud.com | interaction | 2 |
| nextcloud.com | interaction | 2 |
| updates.nextcloud.com | interaction | 1 |
| raw.githubusercontent.com | interaction | 1 |
| github.com | interaction | 1 |
| garm2.nextcloud.com | interaction | 1 |

## n8n-queue-optout-partial

| Domain | Phase | Count |
|--------|-------|-------|

## n8n-queue-optout-full

| Domain | Phase | Count |
|--------|-------|-------|

## nextcloud-optout

| Domain | Phase | Count |
|--------|-------|-------|
| **(none)** | - | - |

*Re-run on 2026-02-19 after fixing opt-out script (`su` -> `runuser`). Opt-out is 100% effective.*


## Orchestration Gap Summary (Experiment B)

| App | Solo Domains | Stack Domains | Stack-Only Domains | Gap? |
|-----|-------------|---------------|-------------------|------|
| n8n | 2 | 2 | 0 | No |
| immich | 0 | 1 | 1 | YES (+1) |
| nextcloud | 7 | 9 | 3 | YES (+3 boot-phase) |

**Note:** Nextcloud stack has 3 boot-phase domains (pushfeed, garm3, apps) not seen in solo until interaction.

## Opt-Out Effectiveness (Experiment C)

| Experiment | Domains Remaining | Zombie Connections? |
|-----------|-------------------|---------------------|
| n8n-queue-optout-partial | 0 | No |
| n8n-queue-optout-full | 0 | No |
| nextcloud-optout | 0 | No |

*All opt-out mechanisms are 100% effective. No zombie connections detected.*

## Anomalies

### immich-solo
```
WARNING: idle.pcap has zero packets
WARNING: interaction.pcap has zero packets
```

