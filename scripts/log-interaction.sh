#!/usr/bin/env bash
# log-interaction.sh - Log user interactions during manual capture.
#
# Usage: ./scripts/log-interaction.sh <data-dir> [description]
# Example: ./scripts/log-interaction.sh data/nextcloud-manual-20260228 "Created admin account"
#
# If no description provided, prompts interactively.

set -euo pipefail

DATA_DIR="${1:?Usage: $0 <data-dir> [description]}"
DESCRIPTION="${2:-}"

LOG_FILE="${DATA_DIR}/interaction-log.txt"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file not found: ${LOG_FILE}"
    echo "Is the capture running?"
    exit 1
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [[ -z "$DESCRIPTION" ]]; then
    echo -n "Interaction description: "
    read -r DESCRIPTION
fi

if [[ -n "$DESCRIPTION" ]]; then
    echo "${TIMESTAMP} - ${DESCRIPTION}" >> "$LOG_FILE"
    echo "Logged: ${TIMESTAMP} - ${DESCRIPTION}"
else
    echo "No description provided, nothing logged."
fi
