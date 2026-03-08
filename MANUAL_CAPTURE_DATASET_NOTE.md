# 72-Hour Manual Capture Dataset Note

This note is here to separate the 72-hour manual-capture results from the automated comparison summary in `data/summary/all-domains-summary.md`.

## What This Dataset Is For

The 72-hour captures are the basis for the periodicity and fingerprint-window claims. They are a different dataset from the automated comparison runs, so their counts should be read on their own terms.

From the archived manual-capture materials, the main takeaways are:

- total unique TLS SNI domains across the three studied applications: `10`
- n8n fingerprint window: `1 hour`
- Immich fingerprint window: `4 hours`
- Nextcloud fingerprint window: `24 hours`

## Relationship To The Automated Comparison
The automated comparison summary uses `12` as the total TLS-domain count for the DockerGym-versus-stack framing. The 72-hour manual-capture dataset has its own total of `10` unique TLS domains. Both numbers are useful, but they answer different questions and come from different runs.

## Archive Note

This public Git snapshot keeps the manual-capture scripts, but not the full raw pcap and log archive behind the final 72-hour results. The archived evidence used for those periodicity claims lives outside this repository snapshot.
