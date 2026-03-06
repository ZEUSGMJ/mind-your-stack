#!/usr/bin/env bash
# analyze-experiment.sh - Complete analysis of one experiment directory.
# Designed to run in background while the next experiment starts.
#
# Usage: ./scripts/analyze-experiment.sh <data-dir>
# Example: ./scripts/analyze-experiment.sh data/n8n-single-20260215_053244

set -euo pipefail

DATA_DIR="${1:?Usage: $0 <data-directory>}"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPERIMENT_NAME=$(basename "$DATA_DIR" | sed 's/-[0-9]\{8\}_[0-9]\{6\}$//')

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ANALYZE]${NC} $*"; }
warn() { echo -e "${YELLOW}[ANALYZE]${NC} $*"; }
err()  { echo -e "${RED}[ANALYZE]${NC} $*" >&2; }

if [[ ! -d "$DATA_DIR" ]]; then
    err "Data directory not found: ${DATA_DIR}"
    exit 1
fi

log "Analyzing: ${EXPERIMENT_NAME} (${DATA_DIR})"

# ── Pcap analysis ─────────────────────────────────────────────────
log "Analyzing pcap files..."
for phase in boot idle interaction; do
    pcap="${DATA_DIR}/${phase}.pcap"
    if [[ -f "$pcap" ]]; then
        "${SCRIPTS_DIR}/analyze-pcap.sh" "$pcap" \
            > "${DATA_DIR}/${phase}-analysis.txt" 2>&1 || warn "${phase} analysis had errors"
    fi
done

# ── DNS log parsing ───────────────────────────────────────────────
log "Parsing DNS logs..."
if [[ -f "${DATA_DIR}/dns-raw.log" ]] && [[ -f "${SCRIPTS_DIR}/parse-dns-logs.sh" ]]; then
    "${SCRIPTS_DIR}/parse-dns-logs.sh" "$DATA_DIR" \
        > "${DATA_DIR}/dns-analysis.txt" 2>&1 || warn "DNS parsing had errors"
fi

# ── Anomaly detection ─────────────────────────────────────────────
log "Running anomaly detection..."
ANOMALIES="${DATA_DIR}/anomalies.txt"
> "$ANOMALIES"

# Check 1: Empty pcaps
for phase in boot idle interaction; do
    pcap="${DATA_DIR}/${phase}.pcap"
    if [[ -f "$pcap" ]]; then
        pcount=$(tshark -r "$pcap" 2>/dev/null | wc -l || echo 0)
        if [[ $pcount -eq 0 ]]; then
            echo "WARNING: ${phase}.pcap has zero packets" >> "$ANOMALIES"
        fi
    else
        echo "WARNING: Missing ${phase}.pcap" >> "$ANOMALIES"
    fi
done

# Check 2: Missing expected files
for file in dns-raw.log metadata.txt; do
    if [[ ! -f "${DATA_DIR}/${file}" ]]; then
        echo "WARNING: Missing ${file}" >> "$ANOMALIES"
    fi
done

# Check 3: Health check failures
if [[ -f "${DATA_DIR}/FAILED.txt" ]]; then
    echo "CRITICAL: Experiment marked FAILED (stack health check failed)" >> "$ANOMALIES"
fi

# Check 4: Full stacks should have external TLS SNI
case "$EXPERIMENT_NAME" in
    n8n-queue|immich|nextcloud|*-optout*)
        external_sni=0
        for phase in boot idle interaction; do
            pcap="${DATA_DIR}/${phase}.pcap"
            if [[ -f "$pcap" ]]; then
                count=$(tshark -r "$pcap" -Y 'tls.handshake.extensions_server_name' \
                    -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
                    | grep -cvE '(^$|\.local$)' || echo 0)
                external_sni=$((external_sni + count))
            fi
        done
        if [[ $external_sni -eq 0 ]]; then
            echo "INFO: Full stack ${EXPERIMENT_NAME} made zero external TLS connections" >> "$ANOMALIES"
        fi
        ;;
esac

# Check 5: Interaction should generate traffic for non-solo experiments
case "$EXPERIMENT_NAME" in
    *-solo) ;; # solo crashes are expected
    *)
        pcap="${DATA_DIR}/interaction.pcap"
        if [[ -f "$pcap" ]]; then
            ipcount=$(tshark -r "$pcap" 2>/dev/null | wc -l || echo 0)
            if [[ $ipcount -eq 0 ]]; then
                echo "WARNING: Interaction phase captured zero packets (Playwright may have failed)" >> "$ANOMALIES"
            fi
        fi
        ;;
esac

if [[ -s "$ANOMALIES" ]]; then
    warn "Anomalies found:"
    while IFS= read -r line; do warn "  $line"; done < "$ANOMALIES"
else
    echo "No anomalies detected." > "$ANOMALIES"
    log "No anomalies detected."
fi

# ── Extract external domains (TLS SNI + DNS) ─────────────────────
log "Extracting external domains..."
DOMAINS_FILE="${DATA_DIR}/external-domains.txt"
{
    echo "# External domains for ${EXPERIMENT_NAME}"
    echo "# Extracted from TLS SNI and CoreDNS logs"
    echo ""
    echo "## TLS SNI by phase"
    for phase in boot idle interaction; do
        pcap="${DATA_DIR}/${phase}.pcap"
        if [[ -f "$pcap" ]]; then
            sni=$(tshark -r "$pcap" -Y 'tls.handshake.extensions_server_name' \
                -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
                | sort | uniq -c | sort -rn || true)
            if [[ -n "$sni" ]]; then
                echo ""
                echo "${phase}:"
                echo "$sni"
            fi
        fi
    done
    echo ""
    echo "## CoreDNS queries (external only)"
    if [[ -f "${DATA_DIR}/dns-raw.log" ]]; then
        grep '\[INFO\]' "${DATA_DIR}/dns-raw.log" \
            | grep -oP '"A(?:AAA)? IN \K[^.]+\.[^"]+(?=\.)' \
            | grep -vE '(example\.com|\.local$|\.arpa$|\.ts\.net$)' \
            | sort | uniq -c | sort -rn || true
    fi
} > "$DOMAINS_FILE" 2>/dev/null

# ── Summary report ────────────────────────────────────────────────
log "Generating summary..."
SUMMARY="${DATA_DIR}/ANALYSIS-SUMMARY.md"

{
    echo "# Analysis Summary: ${EXPERIMENT_NAME}"
    echo ""
    echo "Generated: $(date)"
    echo ""

    for phase in boot idle interaction; do
        f="${DATA_DIR}/${phase}-analysis.txt"
        if [[ -f "$f" ]]; then
            echo "## ${phase^} Phase"
            echo '```'
            cat "$f"
            echo '```'
            echo ""
        fi
    done

    echo "## Anomalies"
    echo '```'
    cat "$ANOMALIES"
    echo '```'
    echo ""

    echo "## External Domains"
    echo '```'
    cat "$DOMAINS_FILE" 2>/dev/null || echo "No domain data"
    echo '```'
    echo ""

    echo "## Files"
    ls -lh "$DATA_DIR/" | tail -n +2
} > "$SUMMARY"

log "Analysis complete: ${DATA_DIR}/ANALYSIS-SUMMARY.md"
