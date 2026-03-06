#!/usr/bin/env bash
# run-experiment.sh - Orchestrates a full lifecycle audit for one app stack.
#
# Usage: sudo ./scripts/run-experiment.sh <experiment-name>
# Example: sudo ./scripts/run-experiment.sh n8n-single
#
# This script:
#   1. Verifies CoreDNS infra is running
#   2. Creates a timestamped data directory
#   3. Runs three capture phases: boot, idle, interaction
#   4. Saves all pcaps and DNS logs
#   5. Tears down the stack cleanly

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
RESEARCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENT_NAME="${1:?Usage: $0 <experiment-name>}"
EXPERIMENT_DIR="${RESEARCH_ROOT}/experiments/${EXPERIMENT_NAME}"
SCRIPTS_DIR="${RESEARCH_ROOT}/scripts"

BOOT_DURATION="${MYS_BOOT:-180}"              # 3 minutes default
IDLE_DURATION="${MYS_IDLE:-3600}"              # 60 minutes default
INTERACTION_DURATION="${MYS_INTERACT:-600}"    # 10 minutes default

COREDNS_CONTAINER="mys-coredns"
COREDNS_IP="172.30.0.2"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATA_DIR="${RESEARCH_ROOT}/data/${EXPERIMENT_NAME}-${TIMESTAMP}"

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[MYS]${NC} $*"; }
warn() { echo -e "${YELLOW}[MYS]${NC} $*"; }
err()  { echo -e "${RED}[MYS]${NC} $*" >&2; }

# ── Preflight Checks ───────────────────────────────────────────────
preflight() {
    log "Running preflight checks..."

    # Must be root (for tcpdump)
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root (for tcpdump). Use sudo."
        exit 1
    fi

    # Check experiment directory exists
    if [[ ! -d "$EXPERIMENT_DIR" ]]; then
        err "Experiment directory not found: ${EXPERIMENT_DIR}"
        err "Available experiments:"
        ls -1 "${RESEARCH_ROOT}/experiments/" 2>/dev/null || echo "  (none)"
        exit 1
    fi

    # Check docker-compose.yml exists
    if [[ ! -f "${EXPERIMENT_DIR}/docker-compose.yml" ]]; then
        err "No docker-compose.yml found in ${EXPERIMENT_DIR}"
        exit 1
    fi

    # Check CoreDNS is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${COREDNS_CONTAINER}$"; then
        warn "CoreDNS is not running. Starting infra..."
        (cd "${RESEARCH_ROOT}/infra" && docker compose up -d)
        sleep 3
    fi

    # Verify CoreDNS responds
    if ! dig @${COREDNS_IP} example.com +short +time=2 +tries=1 > /dev/null 2>&1; then
        err "CoreDNS at ${COREDNS_IP} is not responding. Check infra."
        exit 1
    fi

    # Check tcpdump is available
    if ! command -v tcpdump &> /dev/null; then
        err "tcpdump is not installed. Run: sudo apt install tcpdump"
        exit 1
    fi

    log "Preflight checks passed."
}

# ── Helpers ─────────────────────────────────────────────────────────
get_bridge_interface() {
    # Find the bridge interface for the experiment's Docker network.
    # The network name is derived from the compose project name.
    local project_name="mys-${EXPERIMENT_NAME}"
    local network_name

    # Docker compose creates networks as <project>_default unless named
    # Try the explicit network first, then fall back to default
    network_name=$(docker network ls --format '{{.Name}}' | grep "^${project_name}" | head -1)

    if [[ -z "$network_name" ]]; then
        err "Could not find Docker network for ${project_name}"
        err "Available networks:"
        docker network ls --format '{{.Name}}' | grep -i mys || echo "  (none with mys prefix)"
        return 1
    fi

    # Get the bridge interface ID from the network
    local net_id
    net_id=$(docker network inspect "$network_name" -f '{{.Id}}' | cut -c1-12)
    local iface="br-${net_id}"

    if ip link show "$iface" &>/dev/null; then
        echo "$iface"
    else
        err "Bridge interface ${iface} not found for network ${network_name}"
        return 1
    fi
}

start_capture() {
    local phase="$1"
    local pcap_file="${DATA_DIR}/${phase}.pcap"

    log "Starting packet capture for phase: ${phase}"

    local bridge
    bridge=$(get_bridge_interface)

    # Capture only outbound traffic (not inter-container chatter on the bridge).
    # We exclude traffic destined for the bridge subnet itself.
    tcpdump -i "$bridge" \
        -w "$pcap_file" \
        'not (dst net 172.30.0.0/16 and src net 172.30.0.0/16)' \
        -U \
        &

    echo $! > "${DATA_DIR}/${phase}.tcpdump.pid"
    log "tcpdump PID: $(cat "${DATA_DIR}/${phase}.tcpdump.pid") -> ${pcap_file}"
}

stop_capture() {
    local phase="$1"
    local pid_file="${DATA_DIR}/${phase}.tcpdump.pid"

    if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill -INT "$pid"
            wait "$pid" 2>/dev/null || true
            log "Stopped capture for phase: ${phase}"
        fi
        rm -f "$pid_file"
    fi
}

save_dns_logs() {
    log "Extracting DNS logs from CoreDNS..."
    docker logs "$COREDNS_CONTAINER" > "${DATA_DIR}/dns-raw.log" 2>&1
    log "DNS logs saved to ${DATA_DIR}/dns-raw.log"
}

save_metadata() {
    log "Saving experiment metadata..."
    cat > "${DATA_DIR}/metadata.txt" <<EOF
Experiment: ${EXPERIMENT_NAME}
Timestamp: ${TIMESTAMP}
Date: $(date -Iseconds)
Host: $(hostname)
Docker version: $(docker --version)
Compose file: ${EXPERIMENT_DIR}/docker-compose.yml
Boot duration: ${BOOT_DURATION}s
Idle duration: ${IDLE_DURATION}s
Interaction duration: ${INTERACTION_DURATION}s

--- Running containers at start ---
$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep mys || echo "(none)")

--- Docker networks ---
$(docker network ls | grep mys || echo "(none)")
EOF
}

countdown() {
    local seconds=$1
    local label=$2
    while [ $seconds -gt 0 ]; do
        printf "\r${CYAN}[%s]${NC} %02d:%02d remaining...  " "$label" $((seconds/60)) $((seconds%60))
        sleep 10
        seconds=$((seconds - 10))
    done
    echo ""
}

# ── Health Check & Retry ────────────────────────────────────────────
is_solo_experiment() {
    local exp="$1"
    case "$exp" in
        *-solo|n8n-single) return 0 ;;
        *) return 1 ;;
    esac
}

check_stack_health() {
    local wait_time="${1:-45}"
    log "Health check: waiting ${wait_time}s for containers to stabilize..."
    sleep "$wait_time"

    local project="mys-${EXPERIMENT_NAME}"
    local unhealthy=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name status
        name=$(echo "$line" | cut -d'|' -f1)
        status=$(echo "$line" | cut -d'|' -f2)

        if echo "$status" | grep -qiE 'Exited|Dead'; then
            unhealthy+=("${name}: ${status}")
        fi
    done < <(docker ps -a --filter "name=${project}" --format '{{.Names}}|{{.Status}}' | grep -v coredns)

    if [[ ${#unhealthy[@]} -gt 0 ]]; then
        warn "Unhealthy containers detected:"
        for u in "${unhealthy[@]}"; do
            warn "  - $u"
        done
        return 1
    fi

    log "Health check passed. All containers running."
    return 0
}

diagnose_and_fix() {
    local attempt="$1"

    log "Diagnosing failure (attempt ${attempt}/3)..."
    local logs_dir="${DATA_DIR}/failed-attempt-${attempt}"
    mkdir -p "$logs_dir"

    # Save container logs for diagnosis
    local project="mys-${EXPERIMENT_NAME}"
    docker ps -a --filter "name=${project}" --format '{{.Names}}' | grep -v coredns | while read -r cname; do
        docker logs "$cname" > "${logs_dir}/${cname}.log" 2>&1 || true
    done

    # Save combined logs
    (cd "$EXPERIMENT_DIR" && docker compose -p "${project}" logs --timestamps) \
        > "${logs_dir}/combined.log" 2>&1 || true

    # Check if DB/Redis need more init time
    if docker ps -a --filter "name=${project}" --format '{{.Names}}' | grep -qiE 'postgres|db|redis'; then
        log "DB/Redis detected, waiting extra 30s for initialization..."
        sleep 30
    fi

    # Restart exited containers
    local exited
    exited=$(docker ps -a --filter "name=${project}" --filter "status=exited" --format '{{.Names}}' | grep -v coredns || true)
    if [[ -n "$exited" ]]; then
        log "Restarting exited containers:"
        echo "$exited" | while read -r c; do
            log "  - $c"
            docker start "$c" 2>/dev/null || true
        done
        sleep 10
    fi

    log "Diagnosis saved to ${logs_dir}/"
}

# ── Phase Execution ─────────────────────────────────────────────────
phase_boot() {
    log "════════════════════════════════════════════════════"
    log "PHASE 1: BOOT (${BOOT_DURATION}s)"
    log "════════════════════════════════════════════════════"
    log "Launching stack: ${EXPERIMENT_NAME}"

    # Clear CoreDNS logs so we get a clean baseline.
    docker restart "$COREDNS_CONTAINER" > /dev/null 2>&1
    sleep 2

    local max_attempts=1
    if ! is_solo_experiment "$EXPERIMENT_NAME"; then
        max_attempts=3
        log "Full stack experiment: will retry up to ${max_attempts} times if unhealthy"
    else
        log "Solo experiment: crashes are valid data, will not retry"
    fi

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if [[ $attempt -gt 1 ]]; then
            warn "══ Retry attempt ${attempt}/${max_attempts} ══"
            # Clean up previous failed attempt
            stop_capture "boot" 2>/dev/null || true
            (cd "$EXPERIMENT_DIR" && docker compose -p "mys-${EXPERIMENT_NAME}" down -v 2>/dev/null) || true
            # Explicitly prune any orphaned volumes from this project.
            # docker compose down -v can miss volumes if the compose state is stale.
            local project="mys-${EXPERIMENT_NAME}"
            docker volume ls -q --filter "name=${project}" 2>/dev/null | while read -r vol; do
                warn "Removing orphaned volume: ${vol}"
                docker volume rm "$vol" 2>/dev/null || true
            done
            sleep 5
            # Restart CoreDNS for clean logs
            docker restart "$COREDNS_CONTAINER" > /dev/null 2>&1
            sleep 2
        fi

        # Create containers and networks without starting them.
        (cd "$EXPERIMENT_DIR" && docker compose -p "mys-${EXPERIMENT_NAME}" up --no-start)
        sleep 2

        # Start capture BEFORE starting containers
        start_capture "boot"

        # Now start the containers
        (cd "$EXPERIMENT_DIR" && docker compose -p "mys-${EXPERIMENT_NAME}" start)
        sleep 3

        # Health check for full stack experiments
        if ! is_solo_experiment "$EXPERIMENT_NAME"; then
            if check_stack_health 45; then
                break
            else
                if [[ $attempt -lt $max_attempts ]]; then
                    diagnose_and_fix "$attempt"
                else
                    err "Stack failed health check after ${max_attempts} attempts."
                    err "Proceeding with degraded stack to capture failure data."
                    echo "FAILED: Stack unhealthy after ${max_attempts} retries at $(date)" > "${DATA_DIR}/FAILED.txt"
                    docker ps -a --filter "name=mys-${EXPERIMENT_NAME}" --format '{{.Names}}: {{.Status}}' \
                        >> "${DATA_DIR}/FAILED.txt"
                fi
            fi
        else
            break
        fi

        attempt=$((attempt + 1))
    done

    log "Boot phase: monitoring for ${BOOT_DURATION}s..."
    countdown $BOOT_DURATION "BOOT"

    stop_capture "boot"
    log "Boot phase complete."
}

phase_idle() {
    log "════════════════════════════════════════════════════"
    log "PHASE 2: IDLE (${IDLE_DURATION}s)"
    log "════════════════════════════════════════════════════"
    log "No interaction. Just observing."

    start_capture "idle"

    countdown $IDLE_DURATION "IDLE"

    stop_capture "idle"
    log "Idle phase complete."
}

phase_interaction() {
    log "════════════════════════════════════════════════════"
    log "PHASE 3: INTERACTION (${INTERACTION_DURATION}s)"
    log "════════════════════════════════════════════════════"

    # Show which ports are exposed
    log "Exposed ports:"
    docker ps --format '{{.Names}}: {{.Ports}}' | grep "mys-${EXPERIMENT_NAME}" || true
    echo ""

    start_capture "interaction"

    # Run automated browser interaction if auto-interact.py exists
    local auto_interact="${SCRIPTS_DIR}/auto-interact.py"
    if [[ -f "$auto_interact" ]]; then
        log "Running automated interaction via Playwright..."
        # Run as the non-root user so Playwright can find its browser
        local real_user="${SUDO_USER:-$USER}"
        timeout "${INTERACTION_DURATION}" \
            sudo -u "$real_user" \
            PLAYWRIGHT_BROWSERS_PATH="/home/${real_user}/.cache/ms-playwright" \
            python3 "$auto_interact" "${EXPERIMENT_NAME}" --timeout "${INTERACTION_DURATION}" \
            || warn "Auto-interact finished (timeout or error, non-fatal)"
    else
        warn "No auto-interact.py found, falling back to manual wait."
        warn ">>> INTERACT WITH THE APPLICATION NOW <<<"
        countdown $INTERACTION_DURATION "INTERACT"
    fi

    stop_capture "interaction"
    log "Interaction phase complete."
}

# ── Teardown ────────────────────────────────────────────────────────
save_container_logs() {
    log "Saving container logs before teardown..."
    local containers
    containers=$(docker ps -a --filter "name=mys-${EXPERIMENT_NAME}" --format '{{.Names}}' | grep -v coredns || true)
    for cname in $containers; do
        local logfile="${DATA_DIR}/${cname}.log"
        docker logs "$cname" > "$logfile" 2>&1 || true
        log "  ${cname} -> ${logfile}"
    done
}

teardown() {
    # Save container logs BEFORE tearing down
    save_container_logs

    # Save combined container logs with timestamps (all services in one file)
    log "Saving combined container logs with timestamps..."
    (cd "$EXPERIMENT_DIR" && docker compose -p "mys-${EXPERIMENT_NAME}" logs --timestamps) \
        > "${DATA_DIR}/container-logs.txt" 2>&1 || true

    log "Tearing down stack: ${EXPERIMENT_NAME}"
    (cd "$EXPERIMENT_DIR" && docker compose -p "mys-${EXPERIMENT_NAME}" down -v) || true

    # Clean up any orphaned volumes that docker compose down -v may have missed
    local project="mys-${EXPERIMENT_NAME}"
    local orphaned_vols
    orphaned_vols=$(docker volume ls -q --filter "name=${project}" 2>/dev/null || true)
    if [[ -n "$orphaned_vols" ]]; then
        warn "Cleaning orphaned volumes after teardown:"
        echo "$orphaned_vols" | while read -r vol; do
            warn "  Removing: ${vol}"
            docker volume rm "$vol" 2>/dev/null || true
        done
    fi

    save_dns_logs
    save_metadata

    log "════════════════════════════════════════════════════"
    log "EXPERIMENT COMPLETE: ${EXPERIMENT_NAME}"
    log "Data saved to: ${DATA_DIR}"
    log "════════════════════════════════════════════════════"
    echo ""
    log "Files:"
    ls -lh "${DATA_DIR}/"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
    log "Mind Your Stack - Experiment Runner"
    log "Experiment: ${EXPERIMENT_NAME}"
    log "Data dir:   ${DATA_DIR}"
    echo ""

    preflight

    mkdir -p "$DATA_DIR"

    # Trap to ensure cleanup on interrupt
    trap 'err "Interrupted. Cleaning up..."; stop_capture boot; stop_capture idle; stop_capture interaction; teardown; exit 1' INT TERM

    phase_boot
    phase_idle
    phase_interaction
    teardown
}

main "$@"
