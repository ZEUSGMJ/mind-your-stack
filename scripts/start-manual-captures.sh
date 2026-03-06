#!/usr/bin/env bash
# start-manual-captures.sh - Start all 3 multi-day captures in background
#
# Usage: sudo ./scripts/start-manual-captures.sh [duration-hours]
# Example: sudo ./scripts/start-manual-captures.sh 72
#
# Starts nextcloud, n8n-queue, and immich captures in background.
# You can close the terminal after running this.

set -euo pipefail

DURATION="${1:-72}"
RESEARCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${RESEARCH_ROOT}/scripts"
DATA_DIR="${RESEARCH_ROOT}/data"

echo "Starting 3-day manual captures (${DURATION} hours each)..."
echo ""

# Start each capture in background
nohup "$SCRIPTS_DIR/run-manual-capture.sh" nextcloud "$DURATION" > "${DATA_DIR}/capture-nextcloud.log" 2>&1 &
echo "Nextcloud: started (PID $!, log: data/capture-nextcloud.log)"

sleep 5  # Stagger starts to avoid port conflicts

nohup "$SCRIPTS_DIR/run-manual-capture.sh" n8n-queue "$DURATION" > "${DATA_DIR}/capture-n8n.log" 2>&1 &
echo "n8n-queue: started (PID $!, log: data/capture-n8n.log)"

sleep 5

nohup "$SCRIPTS_DIR/run-manual-capture.sh" immich "$DURATION" > "${DATA_DIR}/capture-immich.log" 2>&1 &
echo "Immich:    started (PID $!, log: data/capture-immich.log)"

echo ""
echo "All captures running in background. You can close this terminal."
echo ""
echo "Access the apps:"
echo "  Nextcloud: http://10.0.0.222:18080"
echo "  n8n:       http://10.0.0.222:5678"
echo "  Immich:    http://10.0.0.222:2283"
echo ""
echo "Check status:  tail -f ${DATA_DIR}/capture-*.log"
echo "Stop all:      sudo pkill -f run-manual-capture.sh"
