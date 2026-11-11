#!/usr/bin/env bash
#
# veron3-deploy watcher — check remote heads cheaply; fetch/build only on changes
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_INTERVAL="${VERON3_POLL_INTERVAL:-60}"
PROJECTS=(lifevault ordretten roni ura trader-ui tendies tendies-showcase visar biomorph cashback cashback-deck cashback-deck-v2 cashback-v2 cashback-v3 blog admin pm-graph argus research-visar events)
exec python3 -u "$SCRIPT_DIR/watcher.py" --interval "$POLL_INTERVAL" "${PROJECTS[@]}"
