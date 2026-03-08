#!/usr/bin/env bash
# run-all.sh - Runs all Mind Your Stack experiments sequentially, unattended.
#
# Usage: sudo ./scripts/run-all.sh
#
# Runs 9 experiments (6 core + 3 opt-out) with:
#   - Smart health checks and retries for full stacks
#   - Background parallel analysis after each experiment
#   - Automated Playwright interaction
#   - Comparisons and summary generation
#
# Experiments:
#   Core (Experiment A+B):
#     1. n8n-single          2. n8n-queue
#     3. immich-solo         4. immich
#     5. nextcloud-solo      6. nextcloud
#   Opt-Out (Experiment C):
#     7. n8n-queue-optout-partial  8. n8n-queue-optout-full
#     9. nextcloud-optout

set -euo pipefail

RESEARCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="${RESEARCH_ROOT}/scripts"
DATA="${RESEARCH_ROOT}/data"
LOGFILE="${DATA}/run-all-$(date +%Y%m%d_%H%M%S).log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[RUN-ALL]${NC} $*" | tee -a "$LOGFILE"; }
warn() { echo -e "${YELLOW}[RUN-ALL]${NC} $*" | tee -a "$LOGFILE"; }
err()  { echo -e "${RED}[RUN-ALL]${NC} $*" | tee -a "$LOGFILE" >&2; }

# ── Preflight ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (for tcpdump). Use: sudo ./scripts/run-all.sh"
    exit 1
fi

mkdir -p "$DATA"

log "Mind Your Stack - Full Experiment Run (v2)"
log "Started at: $(date)"
log "Log file: ${LOGFILE}"
log "Research root: ${RESEARCH_ROOT}"
echo ""

# Track data directories for comparison
declare -A DATA_DIRS
declare -A ANALYSIS_PIDS

# ── Experiment list ────────────────────────────────────────────────
EXPERIMENTS=(
    # Core experiments (Experiment A+B)
    "n8n-single"
    "n8n-queue"
    "immich-solo"
    "immich"
    "nextcloud-solo"
    "nextcloud"
    # Opt-out experiments (Experiment C)
    "n8n-queue-optout-partial"
    "n8n-queue-optout-full"
    "nextcloud-optout"
)

TOTAL=${#EXPERIMENTS[@]}
CURRENT=0

# ── Run each experiment ───────────────────────────────────────────
for exp in "${EXPERIMENTS[@]}"; do
    CURRENT=$((CURRENT + 1))
    log "════════════════════════════════════════════════════════════════"
    log "EXPERIMENT ${CURRENT}/${TOTAL}: ${exp}"
    log "════════════════════════════════════════════════════════════════"
    log "Starting at: $(date)"

    # Check experiment directory exists
    if [[ ! -d "${RESEARCH_ROOT}/experiments/${exp}" ]]; then
        warn "Experiment directory not found: experiments/${exp}, skipping."
        continue
    fi

    # Run the experiment
    if "${SCRIPTS}/run-experiment.sh" "$exp" 2>&1 | tee -a "$LOGFILE"; then
        log "${exp} completed successfully."
    else
        warn "${exp} exited with errors (continuing anyway)."
    fi

    # Find the data directory just created
    latest_dir=$(ls -td "${DATA}/${exp}-"* 2>/dev/null | head -1)
    if [[ -n "$latest_dir" && -d "$latest_dir" ]]; then
        DATA_DIRS["$exp"]="$latest_dir"
        log "Data directory: ${latest_dir}"

        # Launch analysis in background (runs parallel with next experiment)
        log "Launching background analysis for ${exp}..."
        "${SCRIPTS}/analyze-experiment.sh" "$latest_dir" \
            > "${latest_dir}/analysis.log" 2>&1 &
        ANALYSIS_PIDS["$exp"]=$!
        log "Analysis PID: ${ANALYSIS_PIDS[$exp]}"
    else
        warn "No data directory found for ${exp}."
    fi

    # Brief pause between experiments
    log "Waiting 10s before next experiment..."
    sleep 10

    log "Finished ${exp} at: $(date)"
    echo ""
done

# ── Wait for background analysis ─────────────────────────────────
log "════════════════════════════════════════════════════════════════"
log "WAITING FOR BACKGROUND ANALYSIS"
log "════════════════════════════════════════════════════════════════"

for exp in "${!ANALYSIS_PIDS[@]}"; do
    pid="${ANALYSIS_PIDS[$exp]}"
    log "Waiting for ${exp} analysis (PID: ${pid})..."
    if wait "$pid" 2>/dev/null; then
        log "  ${exp} analysis done."
    else
        warn "  ${exp} analysis had errors."
    fi
done

# ── Comparisons ───────────────────────────────────────────────────
log "════════════════════════════════════════════════════════════════"
log "RUNNING COMPARISONS"
log "════════════════════════════════════════════════════════════════"

COMPARISON_DIR="${DATA}/summary"
mkdir -p "$COMPARISON_DIR"

run_comparison() {
    local exp1="$1"
    local exp2="$2"
    local label="$3"

    if [[ -n "${DATA_DIRS[$exp1]:-}" && -n "${DATA_DIRS[$exp2]:-}" ]]; then
        log "Comparing ${exp1} vs ${exp2}..."
        "${SCRIPTS}/compare-experiments.sh" "${DATA_DIRS[$exp1]}" "${DATA_DIRS[$exp2]}" \
            2>&1 | tee -a "$LOGFILE" > "${COMPARISON_DIR}/${label}-comparison.txt" || true
    else
        warn "Skipping comparison ${label}: missing data."
    fi
}

# Experiment B: Solo vs Stack
run_comparison "n8n-single" "n8n-queue" "n8n-stack"
run_comparison "immich-solo" "immich" "immich-stack"
run_comparison "nextcloud-solo" "nextcloud" "nextcloud-stack"

# Experiment C: Stack vs Opt-out
run_comparison "n8n-queue" "n8n-queue-optout-partial" "n8n-optout-partial"
run_comparison "n8n-queue" "n8n-queue-optout-full" "n8n-optout-full"
run_comparison "nextcloud" "nextcloud-optout" "nextcloud-optout"

# ── Summary Table ─────────────────────────────────────────────────
log "════════════════════════════════════════════════════════════════"
log "GENERATING SUMMARY TABLE"
log "════════════════════════════════════════════════════════════════"

SUMMARY_FILE="${COMPARISON_DIR}/all-domains-summary.md"

# Helper: extract TLS SNI domains from pcaps in a directory
extract_sni_domains() {
    local dir="$1"
    for phase in boot idle interaction; do
        local pcap="${dir}/${phase}.pcap"
        [[ -f "$pcap" ]] && \
            tshark -r "$pcap" -Y 'tls.handshake.extensions_server_name' \
                -T fields -e tls.handshake.extensions_server_name 2>/dev/null || true
    done | (grep -vE '(^$|\.local$)' || true) | sort -u
}

cat > "$SUMMARY_FILE" <<HEADER
# Mind Your Stack - External Domains Summary

Generated: $(date)

## All External Domains by App and Phase (TLS SNI)

HEADER

for exp in "${EXPERIMENTS[@]}"; do
    dir="${DATA_DIRS[$exp]:-}"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        echo "## ${exp}" >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        echo "No data available." >> "$SUMMARY_FILE"
        echo "" >> "$SUMMARY_FILE"
        continue
    fi

    echo "## ${exp}" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    echo "| Domain | Phase | Count |" >> "$SUMMARY_FILE"
    echo "|--------|-------|-------|" >> "$SUMMARY_FILE"

    for phase in boot idle interaction; do
        pcap="${dir}/${phase}.pcap"
        if [[ -f "$pcap" ]]; then
            (tshark -r "$pcap" -Y 'tls.handshake.extensions_server_name' \
                -T fields -e tls.handshake.extensions_server_name 2>/dev/null \
                | grep -vE '(^$|\.local$|localhost)' || true) \
                | sort | uniq -c | sort -rn \
                | while read -r count domain; do
                    [[ -z "$domain" ]] && continue
                    echo "| ${domain} | ${phase} | ${count} |" >> "$SUMMARY_FILE"
                done
        fi
    done

    echo "" >> "$SUMMARY_FILE"
done

# Orchestration gap table
cat >> "$SUMMARY_FILE" <<'FOOTER'

## Orchestration Gap Summary (Experiment B)

| App | Solo Domains | Stack Domains | Stack-Only Domains | Gap? |
|-----|-------------|---------------|-------------------|------|
FOOTER

for app in n8n immich nextcloud; do
    solo_key="${app}-single"
    [[ "$app" != "n8n" ]] && solo_key="${app}-solo"

    stack_key="${app}"
    [[ "$app" == "n8n" ]] && stack_key="n8n-queue"

    solo_dir="${DATA_DIRS[$solo_key]:-}"
    stack_dir="${DATA_DIRS[$stack_key]:-}"

    if [[ -n "$solo_dir" && -d "$solo_dir" && -n "$stack_dir" && -d "$stack_dir" ]]; then
        solo_list=$(extract_sni_domains "$solo_dir")
        stack_list=$(extract_sni_domains "$stack_dir")

        solo_count=$(echo "$solo_list" | grep -c . || echo 0)
        stack_count=$(echo "$stack_list" | grep -c . || echo 0)
        stack_only=$(comm -13 <(echo "$solo_list") <(echo "$stack_list") | grep -c . || echo 0)
        gap="No"
        [[ "$stack_only" -gt 0 ]] && gap="YES (+${stack_only})"

        echo "| ${app} | ${solo_count} | ${stack_count} | ${stack_only} | ${gap} |" >> "$SUMMARY_FILE"
    else
        echo "| ${app} | N/A | N/A | N/A | No data |" >> "$SUMMARY_FILE"
    fi
done

# Opt-out table
cat >> "$SUMMARY_FILE" <<'OPTOUT'

## Opt-Out Effectiveness (Experiment C)

| Experiment | Domains Remaining | Zombie Connections? |
|-----------|-------------------|---------------------|
OPTOUT

for exp in n8n-queue-optout-partial n8n-queue-optout-full nextcloud-optout; do
    dir="${DATA_DIRS[$exp]:-}"
    if [[ -n "$dir" && -d "$dir" ]]; then
        domains=$(extract_sni_domains "$dir" | grep -c . || echo 0)
        zombie="No"
        [[ $domains -gt 0 ]] && zombie="Yes (${domains} domains)"
        echo "| ${exp} | ${domains} | ${zombie} |" >> "$SUMMARY_FILE"
    else
        echo "| ${exp} | N/A | No data |" >> "$SUMMARY_FILE"
    fi
done

echo "" >> "$SUMMARY_FILE"

# Check for anomalies across all experiments
echo "## Anomalies" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
for exp in "${EXPERIMENTS[@]}"; do
    dir="${DATA_DIRS[$exp]:-}"
    if [[ -n "$dir" && -f "${dir}/anomalies.txt" ]]; then
        anomaly_content=$(cat "${dir}/anomalies.txt")
        if [[ "$anomaly_content" != "No anomalies detected." ]]; then
            echo "### ${exp}" >> "$SUMMARY_FILE"
            echo '```' >> "$SUMMARY_FILE"
            echo "$anomaly_content" >> "$SUMMARY_FILE"
            echo '```' >> "$SUMMARY_FILE"
            echo "" >> "$SUMMARY_FILE"
        fi
    fi
done

log "Summary saved to: ${SUMMARY_FILE}"

# ── Fix ownership ─────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo nobody)}"
log "Fixing file ownership to ${REAL_USER}..."
chown -R "${REAL_USER}:${REAL_USER}" "${DATA}/" || warn "Could not fix ownership."

# ── Done ──────────────────────────────────────────────────────────
log "════════════════════════════════════════════════════════════════"
log "ALL EXPERIMENTS COMPLETE"
log "════════════════════════════════════════════════════════════════"
log "Finished at: $(date)"
log "Data in: ${DATA}/"
log "Summary: ${COMPARISON_DIR}/all-domains-summary.md"
log "Comparisons:"
ls -1 "${COMPARISON_DIR}/"*.txt 2>/dev/null | while read -r f; do
    log "  $(basename "$f")"
done
log "Log: ${LOGFILE}"
