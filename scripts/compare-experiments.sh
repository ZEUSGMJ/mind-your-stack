#!/usr/bin/env bash
# compare-experiments.sh - Side-by-side comparison of two experiment data directories.
#
# Usage: ./scripts/compare-experiments.sh <data-dir-1> <data-dir-2>
# Example: ./scripts/compare-experiments.sh data/n8n-single-20260215_* data/n8n-queue-20260215_*

set -euo pipefail

DIR1="${1:?Usage: $0 <data-dir-1> <data-dir-2>}"
DIR2="${2:?Usage: $0 <data-dir-1> <data-dir-2>}"

NAME1=$(basename "$DIR1")
NAME2=$(basename "$DIR2")

echo "════════════════════════════════════════════════════════════════"
echo "COMPARISON: ${NAME1} vs ${NAME2}"
echo "════════════════════════════════════════════════════════════════"

extract_domains() {
    local dir="$1"
    local domains=""
    for phase in boot idle interaction; do
        local pcap="${dir}/${phase}.pcap"
        if [[ -f "$pcap" ]]; then
            tshark -r "$pcap" -Y 'dns.flags.response == 0' \
                -T fields -e dns.qry.name 2>/dev/null || true
        fi
    done | sort -u | grep -v '^$' || true
}

extract_sni() {
    local dir="$1"
    for phase in boot idle interaction; do
        local pcap="${dir}/${phase}.pcap"
        if [[ -f "$pcap" ]]; then
            tshark -r "$pcap" -Y 'tls.handshake.extensions_server_name' \
                -T fields -e tls.handshake.extensions_server_name 2>/dev/null || true
        fi
    done | sort -u | grep -v '^$' || true
}

extract_ips() {
    local dir="$1"
    for phase in boot idle interaction; do
        local pcap="${dir}/${phase}.pcap"
        if [[ -f "$pcap" ]]; then
            tshark -r "$pcap" -T fields -e ip.dst 2>/dev/null || true
        fi
    done | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|$)' \
        | sort -u || true
}

echo ""
echo "--- DNS Domains ---"
echo ""
DOMAINS1=$(extract_domains "$DIR1")
DOMAINS2=$(extract_domains "$DIR2")

echo "Only in ${NAME1}:"
comm -23 <(echo "$DOMAINS1") <(echo "$DOMAINS2") | sed 's/^/  /'
echo ""
echo "Only in ${NAME2}:"
comm -13 <(echo "$DOMAINS1") <(echo "$DOMAINS2") | sed 's/^/  /'
echo ""
echo "In both:"
comm -12 <(echo "$DOMAINS1") <(echo "$DOMAINS2") | sed 's/^/  /'

echo ""
echo "--- TLS SNI ---"
echo ""
SNI1=$(extract_sni "$DIR1")
SNI2=$(extract_sni "$DIR2")

echo "Only in ${NAME1}:"
comm -23 <(echo "$SNI1") <(echo "$SNI2") | sed 's/^/  /'
echo ""
echo "Only in ${NAME2}:"
comm -13 <(echo "$SNI1") <(echo "$SNI2") | sed 's/^/  /'
echo ""
echo "In both:"
comm -12 <(echo "$SNI1") <(echo "$SNI2") | sed 's/^/  /'

echo ""
echo "--- Outbound IPs (non-RFC1918) ---"
echo ""
IPS1=$(extract_ips "$DIR1")
IPS2=$(extract_ips "$DIR2")

echo "Only in ${NAME1}:"
comm -23 <(echo "$IPS1") <(echo "$IPS2") | sed 's/^/  /'
echo ""
echo "Only in ${NAME2}:"
comm -13 <(echo "$IPS1") <(echo "$IPS2") | sed 's/^/  /'
echo ""
echo "In both:"
comm -12 <(echo "$IPS1") <(echo "$IPS2") | sed 's/^/  /'

echo ""
echo "--- Per-Phase Packet Counts ---"
echo ""
printf "%-15s %-10s %-10s\n" "Phase" "$NAME1" "$NAME2"
printf "%-15s %-10s %-10s\n" "-----" "------" "------"
for phase in boot idle interaction; do
    c1=0; c2=0
    [[ -f "${DIR1}/${phase}.pcap" ]] && c1=$(tshark -r "${DIR1}/${phase}.pcap" 2>/dev/null | wc -l)
    [[ -f "${DIR2}/${phase}.pcap" ]] && c2=$(tshark -r "${DIR2}/${phase}.pcap" 2>/dev/null | wc -l)
    printf "%-15s %-10s %-10s\n" "$phase" "$c1" "$c2"
done

echo ""
echo "Comparison complete."
