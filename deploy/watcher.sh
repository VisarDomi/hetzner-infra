#!/usr/bin/env bash
#
# veron3-deploy watcher — polls all projects every 60s, deploys when origin/main changes
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POLL_INTERVAL="${VERON3_POLL_INTERVAL:-60}"
PROJECTS=(lifevault ordretten roni ura trader-ui tendies visar biomorph cashback cashback-deck cashback-biz blog admin)
LOCKFILE="/tmp/veron3-deploy.lock"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT

log "veron3-deploy watcher started (polling every ${POLL_INTERVAL}s)"
log "Watching projects: ${PROJECTS[*]}"

while true; do
    # Skip this cycle if a previous one is still running
    if [ -f "$LOCKFILE" ]; then
        LOCK_PID=$(cat "$LOCKFILE" 2>/dev/null)
        if kill -0 "$LOCK_PID" 2>/dev/null; then
            log "Previous cycle still running (PID $LOCK_PID) — skipping"
            sleep "$POLL_INTERVAL"
            continue
        fi
        # Stale lockfile — remove it
        rm -f "$LOCKFILE"
    fi

    echo $$ > "$LOCKFILE"

    for project in "${PROJECTS[@]}"; do
        # Run each deploy in a subshell so a failure in one doesn't stop others
        "$SCRIPT_DIR/deploy.sh" "$project" 2>&1 || {
            log "WARNING: $project deploy check failed (will retry next cycle)"
        }
    done

    rm -f "$LOCKFILE"
    sleep "$POLL_INTERVAL"
done
