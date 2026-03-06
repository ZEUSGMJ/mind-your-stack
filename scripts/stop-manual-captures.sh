#!/usr/bin/env bash
# stop-manual-captures.sh - Stop all running manual captures and their containers
#
# Usage: sudo ./scripts/stop-manual-captures.sh

set -euo pipefail

RESEARCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Stopping manual captures..."

# Kill capture scripts
pkill -f "run-manual-capture.sh" 2>/dev/null || true

# Kill any orphaned tcpdump processes
pkill -f "tcpdump.*hour-" 2>/dev/null || true

sleep 2

# Stop all experiment containers (keep volumes for data persistence)
echo "Stopping containers (keeping data)..."

for experiment in nextcloud n8n-queue immich; do
    compose_file="${RESEARCH_ROOT}/experiments/${experiment}/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        docker compose -p "mys-${experiment}" -f "$compose_file" down 2>/dev/null || true
    fi
done

echo ""
echo "Data volumes preserved. To delete all data, run:"
echo "  docker volume ls -q --filter 'name=mys-' | xargs -r docker volume rm"

echo ""
echo "All captures and containers stopped."

# Show what data was captured
echo ""
echo "Captured data:"
ls -d ${RESEARCH_ROOT}/data/*-manual-* 2>/dev/null || echo "(none)"
