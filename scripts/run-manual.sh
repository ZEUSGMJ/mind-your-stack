#!/bin/bash
# run-manual.sh - Run a single experiment with manual browser interaction
# Usage: sudo ./scripts/run-manual.sh <experiment-name>
#
# This script:
# 1. Starts the experiment containers
# 2. Captures all traffic (boot + your manual interaction)
# 3. Waits for you to press Enter when done
# 4. Saves the pcap and logs

set -euo pipefail

EXPERIMENT="${1:-}"
if [ -z "$EXPERIMENT" ]; then
    echo "Usage: sudo $0 <experiment-name>"
    echo ""
    echo "Available experiments:"
    ls -1 experiments/ | grep -v README
    exit 1
fi

COMPOSE_FILE="experiments/${EXPERIMENT}/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: Compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Create output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="data/${EXPERIMENT}-manual-${TIMESTAMP}"
mkdir -p "$OUTDIR"

echo "=============================================="
echo "Manual Interaction Run: $EXPERIMENT"
echo "Output: $OUTDIR"
echo "=============================================="
echo ""

# Clean up any previous run
echo "[1/5] Cleaning up previous containers..."
docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" down -v 2>/dev/null || true
docker volume ls -q --filter "name=mys-${EXPERIMENT}" | xargs -r docker volume rm 2>/dev/null || true

# Find the bridge interface (will be created when containers start)
echo "[2/5] Starting containers..."
docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" up -d

# Wait for containers and find bridge interface
sleep 5
BRIDGE=$(docker network inspect "mys-${EXPERIMENT}_internal" --format '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null || echo "")
if [ -z "$BRIDGE" ]; then
    BRIDGE=$(docker network ls --filter "name=mys-${EXPERIMENT}" --format '{{.ID}}' | head -1 | xargs -I{} docker network inspect {} --format '{{.Options.com.docker.network.bridge.name}}' 2>/dev/null | head -1 || echo "")
fi

if [ -z "$BRIDGE" ]; then
    echo "WARNING: Could not find bridge interface, using docker0"
    BRIDGE="docker0"
fi

# Start packet capture
echo "[3/5] Starting packet capture on $BRIDGE..."
tcpdump -i "$BRIDGE" -w "${OUTDIR}/capture.pcap" \
    'not (src net 172.16.0.0/12 and dst net 172.16.0.0/12)' \
    2>/dev/null &
TCPDUMP_PID=$!
echo "$TCPDUMP_PID" > "${OUTDIR}/tcpdump.pid"

# Show access info
echo ""
echo "=============================================="
echo "READY FOR MANUAL INTERACTION"
echo "=============================================="
echo ""

# Get the port
PORT=$(docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" ps --format json 2>/dev/null | jq -r '.[].Publishers[]?.PublishedPort // empty' | head -1 || echo "")
if [ -z "$PORT" ]; then
    # Fallback: parse from compose file
    PORT=$(grep -A1 "ports:" "$COMPOSE_FILE" | grep -oP '\d+(?=:)' | head -1 || echo "unknown")
fi

echo "Access URL: http://10.0.0.222:${PORT}"
echo ""
echo "Credentials (if needed):"
echo "  Username: admin"
echo "  Password: admin_research_pw"
echo ""
echo "Container status:"
docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" ps
echo ""
echo "=============================================="
echo "Press ENTER when you're done interacting..."
echo "=============================================="
read -r

# Stop capture
echo ""
echo "[4/5] Stopping capture..."
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true

# Save logs
echo "[5/5] Saving logs..."
docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" logs --timestamps > "${OUTDIR}/container-logs.txt" 2>&1

# Extract domains
echo "Extracting TLS SNI domains..."
tshark -r "${OUTDIR}/capture.pcap" -Y "tls.handshake.extensions_server_name" \
    -T fields -e tls.handshake.extensions_server_name 2>/dev/null | \
    sort | uniq -c | sort -rn > "${OUTDIR}/external-domains.txt"

# Tear down
echo "Tearing down containers..."
docker compose -p "mys-${EXPERIMENT}" -f "$COMPOSE_FILE" down -v

# Summary
echo ""
echo "=============================================="
echo "COMPLETE"
echo "=============================================="
echo "Output directory: $OUTDIR"
echo ""
echo "External domains found:"
cat "${OUTDIR}/external-domains.txt" || echo "(none)"
echo ""
