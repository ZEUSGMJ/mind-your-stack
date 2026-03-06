#!/usr/bin/env bash
# parse-dns-logs.sh - Parse CoreDNS logs and summarize queried domains.
#
# Usage: ./scripts/parse-dns-logs.sh <data-directory>
# Example: ./scripts/parse-dns-logs.sh data/n8n-single-20260206_140000

set -euo pipefail

DATA_DIR="${1:?Usage: $0 <data-directory>}"
DNS_LOG="${DATA_DIR}/dns-raw.log"

if [[ ! -f "$DNS_LOG" ]]; then
    echo "Error: DNS log not found at ${DNS_LOG}"
    exit 1
fi

echo "========================================"
echo "DNS Analysis: $(basename "$DATA_DIR")"
echo "========================================"
echo ""

# Extract queried domain names from CoreDNS log format.
# CoreDNS log lines look like:
# [INFO] 172.30.0.5:43210 - 12345 "A IN example.com. udp 40 false 4096" ...
echo "--- All Queried Domains (unique, sorted by frequency) ---"
grep -oP '"[A-Z]+ IN \K[^ ]+' "$DNS_LOG" \
    | sed 's/\.$//' \
    | sort \
    | uniq -c \
    | sort -rn \
    | head -50

echo ""
echo "--- Summary ---"
TOTAL_QUERIES=$(grep -c '"[A-Z]* IN ' "$DNS_LOG" 2>/dev/null || echo 0)
UNIQUE_DOMAINS=$(grep -oP '"[A-Z]+ IN \K[^ ]+' "$DNS_LOG" | sed 's/\.$//' | sort -u | wc -l)
echo "Total DNS queries: ${TOTAL_QUERIES}"
echo "Unique domains:    ${UNIQUE_DOMAINS}"

echo ""
echo "--- Domains by Type ---"
echo "A records:"
grep -oP '"A IN \K[^ ]+' "$DNS_LOG" | sed 's/\.$//' | sort -u | head -20
echo ""
echo "AAAA records:"
grep -oP '"AAAA IN \K[^ ]+' "$DNS_LOG" | sed 's/\.$//' | sort -u | head -20

echo ""
echo "--- External vs Local ---"
echo "External domains (not .local, not internal):"
grep -oP '"[A-Z]+ IN \K[^ ]+' "$DNS_LOG" \
    | sed 's/\.$//' \
    | grep -v '\.local$' \
    | grep -v '^localhost$' \
    | grep -v '\.internal$' \
    | sort -u

echo ""
echo "Analysis complete. Raw log: ${DNS_LOG}"
