#!/usr/bin/env bash
#
# check-subdomains.sh — warns if Caddyfile has subdomains not listed in admin portal
#
# Compares subdomains in the server's Caddyfile against the services.ts data file.
# Runs after admin deploys to catch drift. Can also be run standalone.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="erdal@157.90.28.14"
SERVICES_TS="$SCRIPT_DIR/../projects-portal/src/lib/data/services.ts"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUBDOMAIN-CHECK: $*"
}

# 1. Get all subdomains from Caddyfile (exclude www redirects and the admin portal itself)
CADDY_DOMAINS=$(ssh "$SERVER" "grep -oE '^[a-zA-Z0-9._-]+\.veron3\.space' /etc/caddy/Caddyfile" 2>/dev/null | sort -u)
CADDY_CUSTOM=$(ssh "$SERVER" "grep -oE '^[a-zA-Z0-9._-]+\.(com|org|net)' /etc/caddy/Caddyfile" 2>/dev/null | grep -v '^www\.' | sort -u)
ALL_CADDY=$(echo -e "$CADDY_DOMAINS\n$CADDY_CUSTOM" | grep -v '^$' | sort -u)

# 2. Get all domains listed in services.ts
SERVICES_DOMAINS=$(grep -oE "domain: '[^']+'" "$SERVICES_TS" 2>/dev/null | sed "s/domain: '//;s/'//" | sort -u)

# 3. Domains to skip (admin portal lists itself, no need to self-reference)
SKIP="admin.veron3.space"

# 4. Diff
MISSING=()
while IFS= read -r domain; do
    [[ -z "$domain" ]] && continue
    [[ "$domain" == "$SKIP" ]] && continue
    if ! echo "$SERVICES_DOMAINS" | grep -qxF "$domain"; then
        MISSING+=("$domain")
    fi
done <<< "$ALL_CADDY"

if [[ ${#MISSING[@]} -eq 0 ]]; then
    log "All Caddyfile subdomains are listed in admin portal"
    exit 0
else
    log "WARNING: ${#MISSING[@]} subdomain(s) in Caddyfile but NOT in admin portal:"
    for d in "${MISSING[@]}"; do
        log "  - $d"
    done
    exit 1
fi
