#!/usr/bin/env bash
# run-manual-capture.sh - Multi-day continuous capture with hourly rotation.
#
# Usage: sudo ./scripts/run-manual-capture.sh <experiment-name> [duration-hours]
# Example: sudo ./scripts/run-manual-capture.sh nextcloud 72
#
# This script:
#   1. Starts the experiment stack
#   2. Captures traffic in 1-hour rotations
#   3. Runs incremental analysis after each hour
#   4. Continues until duration reached or interrupted
#
# The user can interact with the app at any time.
# Use scripts/log-interaction.sh to log interaction timestamps.

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
RESEARCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENT_NAME="${1:?Usage: $0 <experiment-name> [duration-hours]}"
DURATION_HOURS="${2:-72}"  # Default 3 days
EXPERIMENT_DIR="${RESEARCH_ROOT}/experiments/${EXPERIMENT_NAME}"
SCRIPTS_DIR="${RESEARCH_ROOT}/scripts"

COREDNS_CONTAINER="mys-coredns"
COREDNS_IP="172.30.0.2"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA_DIR="${RESEARCH_ROOT}/data/${EXPERIMENT_NAME}-manual-${TIMESTAMP}"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[MYS-MANUAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[MYS-MANUAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"; }
err()  { echo -e "${RED}[MYS-MANUAL]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

# ── Trap for clean shutdown ─────────────────────────────────────────
CURRENT_TCPDUMP_PID=""
cleanup() {
    log "Caught interrupt signal. Cleaning up..."

    # Stop current capture
    if [[ -n "$CURRENT_TCPDUMP_PID" ]] && kill -0 "$CURRENT_TCPDUMP_PID" 2>/dev/null; then
        kill -INT "$CURRENT_TCPDUMP_PID" 2>/dev/null || true
        wait "$CURRENT_TCPDUMP_PID" 2>/dev/null || true
    fi

    # Save container logs
    log "Saving container logs..."
    docker compose -p "mys-${EXPERIMENT_NAME}" logs --timestamps > "${DATA_DIR}/container-logs.txt" 2>&1 || true

    # Stop stack (keep volumes for data persistence)
    log "Stopping stack (keeping data)..."
    docker compose -p "mys-${EXPERIMENT_NAME}" -f "${EXPERIMENT_DIR}/docker-compose.yml" down 2>/dev/null || true

    # Final summary
    local total_pcaps
    total_pcaps=$(ls -1 "${DATA_DIR}"/hour-*.pcap 2>/dev/null | wc -l || echo 0)
    log "Capture ended. ${total_pcaps} hourly pcap files saved to ${DATA_DIR}"

    exit 0
}
trap cleanup SIGINT SIGTERM

# ── Preflight Checks ───────────────────────────────────────────────
preflight() {
    log "Running preflight checks..."

    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root (for tcpdump). Use sudo."
        exit 1
    fi

    if [[ ! -d "$EXPERIMENT_DIR" ]]; then
        err "Experiment directory not found: ${EXPERIMENT_DIR}"
        exit 1
    fi

    if [[ ! -f "${EXPERIMENT_DIR}/docker-compose.yml" ]]; then
        err "No docker-compose.yml found in ${EXPERIMENT_DIR}"
        exit 1
    fi

    # Check/start CoreDNS
    if ! docker ps --format '{{.Names}}' | grep -q "^${COREDNS_CONTAINER}$"; then
        warn "CoreDNS is not running. Starting infra..."
        (cd "${RESEARCH_ROOT}/infra" && docker compose up -d)
        sleep 3
    fi

    if ! dig @${COREDNS_IP} example.com +short +time=2 +tries=1 > /dev/null 2>&1; then
        err "CoreDNS at ${COREDNS_IP} is not responding."
        exit 1
    fi

    if ! command -v tcpdump &> /dev/null; then
        err "tcpdump is not installed."
        exit 1
    fi

    log "Preflight checks passed."
}

# ── Get bridge interface ───────────────────────────────────────────
get_bridge_interface() {
    local project_name="mys-${EXPERIMENT_NAME}"
    local network_name

    network_name=$(docker network ls --format '{{.Name}}' | grep "^${project_name}" | head -1)

    if [[ -z "$network_name" ]]; then
        err "Could not find Docker network for ${project_name}"
        return 1
    fi

    local net_id
    net_id=$(docker network inspect "$network_name" -f '{{.Id}}' | cut -c1-12)
    local iface="br-${net_id}"

    if ip link show "$iface" &>/dev/null; then
        echo "$iface"
    else
        err "Bridge interface ${iface} not found"
        return 1
    fi
}

# ── Main ────────────────────────────────────────────────────────────
main() {
    preflight

    mkdir -p "$DATA_DIR"
    log "Data directory: ${DATA_DIR}"
    log "Duration: ${DURATION_HOURS} hours"

    # Initialize interaction log
    echo "# Interaction Log for ${EXPERIMENT_NAME}" > "${DATA_DIR}/interaction-log.txt"
    echo "# Add timestamps when you interact with the app" >> "${DATA_DIR}/interaction-log.txt"
    echo "# Format: YYYY-MM-DD HH:MM:SS - description" >> "${DATA_DIR}/interaction-log.txt"
    echo "" >> "${DATA_DIR}/interaction-log.txt"

    # Save metadata
    cat > "${DATA_DIR}/metadata.txt" << EOF
Experiment: ${EXPERIMENT_NAME}
Type: manual-capture
Start Time: $(date -Iseconds)
Planned Duration: ${DURATION_HOURS} hours
Capture Mode: hourly rotation
Data Directory: ${DATA_DIR}
EOF

    # Start the stack
    log "Starting experiment stack: mys-${EXPERIMENT_NAME}"
    docker compose -p "mys-${EXPERIMENT_NAME}" -f "${EXPERIMENT_DIR}/docker-compose.yml" up -d

    # Wait for containers to be healthy
    log "Waiting 60 seconds for containers to initialize..."
    sleep 60

    # Get bridge interface
    local bridge
    bridge=$(get_bridge_interface)
    log "Capturing on bridge: ${bridge}"

    # Print access info
    log "=========================================="
    log "Stack is running. You can now interact with the app."
    log "To log interactions: ./scripts/log-interaction.sh ${DATA_DIR}"
    log "Press Ctrl+C to stop capture and tear down."
    log "=========================================="

    # Main capture loop
    local hour
    for hour in $(seq 1 "$DURATION_HOURS"); do
        local pcap_file="${DATA_DIR}/hour-$(printf '%03d' "$hour").pcap"
        local hour_start
        hour_start=$(date '+%Y-%m-%d %H:%M:%S')

        log "Hour ${hour}/${DURATION_HOURS} - Starting capture -> ${pcap_file}"

        # Start tcpdump for this hour
        tcpdump -i "$bridge" \
            -w "$pcap_file" \
            'not (dst net 172.30.0.0/16 and src net 172.30.0.0/16)' \
            -U &
        CURRENT_TCPDUMP_PID=$!

        # Sleep for 1 hour
        sleep 3600

        # Stop this hour's capture
        if kill -0 "$CURRENT_TCPDUMP_PID" 2>/dev/null; then
            kill -INT "$CURRENT_TCPDUMP_PID"
            wait "$CURRENT_TCPDUMP_PID" 2>/dev/null || true
        fi
        CURRENT_TCPDUMP_PID=""

        # Quick stats for this hour
        local pcap_size
        pcap_size=$(du -h "$pcap_file" 2>/dev/null | cut -f1 || echo "?")
        log "Hour ${hour} complete. Pcap size: ${pcap_size}"

        # Run incremental analysis in background (don't block next hour)
        if [[ -f "${SCRIPTS_DIR}/analyze-pcap.sh" ]]; then
            "${SCRIPTS_DIR}/analyze-pcap.sh" "$pcap_file" > "${pcap_file%.pcap}-analysis.txt" 2>&1 &
        fi
    done

    log "Capture duration complete (${DURATION_HOURS} hours)."
    cleanup
}

main "$@"
