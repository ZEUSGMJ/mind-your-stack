#!/usr/bin/env bash
# analyze-pcap.sh - Quick analysis of a pcap file from an experiment.
#
# Usage: ./scripts/analyze-pcap.sh <pcap-file>
# Example: ./scripts/analyze-pcap.sh data/n8n-single-20260206_140000/boot.pcap

set -euo pipefail

PCAP="${1:?Usage: $0 <pcap-file>}"

if [[ ! -f "$PCAP" ]]; then
    echo "Error: File not found: ${PCAP}"
    exit 1
fi

PHASE=$(basename "$PCAP" .pcap)
EXPERIMENT=$(basename "$(dirname "$PCAP")")

echo "========================================"
echo "PCAP Analysis: ${EXPERIMENT} / ${PHASE}"
echo "========================================"

echo ""
echo "--- DNS Queries (unique domains) ---"
tshark -r "$PCAP" -Y 'dns.flags.response == 0' \
    -T fields -e dns.qry.name 2>/dev/null \
    | sort | uniq -c | sort -rn | head -30

echo ""
echo "--- TLS SNI (Server Name Indication) ---"
tshark -r "$PCAP" -Y 'tls.handshake.extensions_server_name' \
    -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
    | sort | uniq -c | sort -rn | head -30

echo ""
echo "--- HTTP Host Headers ---"
tshark -r "$PCAP" -Y 'http.host' \
    -T fields -e http.host 2>/dev/null \
    | sort | uniq -c | sort -rn | head -30

echo ""
echo "--- Outbound Destination IPs (non-RFC1918, top 20) ---"
tshark -r "$PCAP" -T fields -e ip.dst 2>/dev/null \
    | grep -v '^$' \
    | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)' \
    | sort | uniq -c | sort -rn | head -20

echo ""
echo "--- Protocol Breakdown ---"
tshark -r "$PCAP" -T fields -e frame.protocols 2>/dev/null \
    | tr ':' '\n' | sort | uniq -c | sort -rn | head -15

echo ""
echo "--- Capture Stats ---"
TOTAL_PACKETS=$(tshark -r "$PCAP" 2>/dev/null | wc -l)
DURATION=$(tshark -r "$PCAP" -T fields -e frame.time_relative 2>/dev/null | tail -1)
echo "Total packets: ${TOTAL_PACKETS}"
echo "Duration:      ${DURATION:-unknown}s"

echo ""
echo "Analysis complete."
