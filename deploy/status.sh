#!/usr/bin/env bash
#
# Show deploy status for all projects
# Reads project list from deploy.sh config automatically
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="/home/visar/Documents/wip/hetzner"
STATE_DIR="$SCRIPT_DIR/.state"

# Source the project config from deploy.sh (just the REPO_DIRS array)
eval "$(grep -A100 '^declare -A REPO_DIRS=' "$SCRIPT_DIR/deploy.sh" | head -n $(grep -A100 '^declare -A REPO_DIRS=' "$SCRIPT_DIR/deploy.sh" | grep -n ')' | head -1 | cut -d: -f1))"

printf "%-12s %-10s %-10s %s\n" "PROJECT" "DEPLOYED" "LATEST" "STATUS"
printf "%-12s %-10s %-10s %s\n" "-------" "--------" "------" "------"

for project in "${!REPO_DIRS[@]}"; do
    repo_dir="$WORKSPACE/${REPO_DIRS[$project]}"
    sha_file="$STATE_DIR/$project.sha"

    # Fetch silently
    git -C "$repo_dir" fetch origin main 2>/dev/null

    deployed=$(cat "$sha_file" 2>/dev/null | head -c 7 || echo "never")
    [[ "$deployed" == "" ]] && deployed="never"
    latest=$(git -C "$repo_dir" rev-parse --short origin/main 2>/dev/null || echo "???")

    if [[ "$deployed" == "never" ]]; then
        status="NOT DEPLOYED"
    elif [[ "$deployed" == "$latest" ]]; then
        status="up to date"
    else
        status="OUTDATED"
    fi

    printf "%-12s %-10s %-10s %s\n" "$project" "$deployed" "$latest" "$status"
done | sort

echo ""

# Show watcher status
if systemctl --user is-active veron3-deploy.service &>/dev/null; then
    echo "Watcher: RUNNING (systemd)"
elif pgrep -f "watcher.sh" &>/dev/null; then
    echo "Watcher: RUNNING (manual)"
else
    echo "Watcher: STOPPED"
fi

if systemctl --user is-active veron3-webhook.service &>/dev/null; then
    echo "Webhook: RUNNING (systemd)"
elif systemctl --user is-active webhook.service &>/dev/null; then
    echo "Webhook: RUNNING (legacy unit)"
else
    echo "Webhook: STOPPED"
fi
