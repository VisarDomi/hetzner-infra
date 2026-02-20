#!/usr/bin/env bash
#
# veron3 deploy — builds from origin/main without touching the working tree
#
# Usage: ./deploy.sh <project>
#
# To add a new project, edit the config arrays below and add the project name
# to PROJECTS in watcher.sh. See deploy/README.md for full instructions.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="/home/visar/Documents/wip/hetzner"
BUILD_BASE="/tmp/veron3-build"
DEPLOY_STATE_DIR="$SCRIPT_DIR/.state"
LOCKFILE_CACHE_DIR="$SCRIPT_DIR/.cache"
LOG_DIR="$SCRIPT_DIR/logs"
SERVER="erdal@157.90.28.14"

mkdir -p "$DEPLOY_STATE_DIR" "$LOCKFILE_CACHE_DIR" "$LOG_DIR"

# =============================================================================
# PROJECT CONFIGURATION — add new projects here
# =============================================================================
#
# Required for each project:
#   REPO_DIRS     — repo directory name under $WORKSPACE
#   SERVER_PATHS  — where to deploy on the server
#   DEPLOY_TYPES  — "node" (rsync build + npm ci + restart) or "static" (rsync only)
#   BUILD_CMDS    — command to build (runs inside the extracted source dir)
#   BUILD_OUTPUTS — directory containing build output (relative to build dir)
#
# Optional:
#   SERVICE_NAMES — systemd service to restart (node deploy type only)
#   ENV_FILES     — .env file to copy from working dir before build
#   NODE_FILES    — extra files to rsync for node deploys (default: package.json package-lock.json)

declare -A REPO_DIRS=(
    [lifevault]="life-document-organizer"
    [ordretten]="ordretten"
    [roni]="roni-application-tracker"
    [ura]="ura"

    [trader-ui]="trader-ui"
    [tendies]="trader-svelte"
    [visar]="visar-dev-site"
    [biomorph]="biomorph-website"
    [cashback]="cashback"
    [cashback-deck]="cashback-deck"
    [cashback-biz]="cashback-biz"
)

declare -A SERVER_PATHS=(
    [lifevault]="/home/erdal/lifevault"
    [ordretten]="/home/erdal/ordretten"
    [roni]="/home/erdal/roni"
    [ura]="/home/erdal/ura"

    [trader-ui]="/home/erdal/trader-ui"
    [tendies]="/home/erdal/tendies"
    [visar]="/home/erdal/visar"
    [biomorph]="/home/erdal/biomorph"
    [cashback]="/home/erdal/cashback"
    [cashback-deck]="/home/erdal/cashback-deck"
    [cashback-biz]="/home/erdal/cashback-biz"
)

declare -A DEPLOY_TYPES=(
    [lifevault]="node"
    [ordretten]="node"
    [roni]="static"
    [ura]="static"

    [trader-ui]="node"
    [tendies]="node"
    [visar]="node"
    [biomorph]="static"
    [cashback]="static"
    [cashback-deck]="static"
    [cashback-biz]="static"
)

declare -A INSTALL_CMDS=(
    [lifevault]="npm ci"
    [ordretten]="npm ci"
    [roni]="npm ci"
    [ura]="npm ci"

    [trader-ui]="npm ci"
    [tendies]="npm ci"
    [visar]="npm ci"
    [biomorph]="npm install"
    [cashback]="npm ci"
    [cashback-deck]="npm ci"
    [cashback-biz]="npm ci"
)

declare -A BUILD_CMDS=(
    [lifevault]="npm run build"
    [ordretten]="npm run build"
    [roni]="npm run build"
    [ura]="npx ng build"

    [trader-ui]="npm run build"
    [tendies]="npm run build"
    [visar]="npm run build && python3 -m weasyprint static/cv.html build/client/visar-domi-cv.pdf"
    [biomorph]="npm run build"
    [cashback]="npm run build"
    [cashback-deck]="npm run build"
    [cashback-biz]="npm run build"
)

# Path to the build output directory (relative to the extracted source root)
declare -A BUILD_OUTPUTS=(
    [lifevault]="build"
    [ordretten]="build"
    [roni]="dist"
    [ura]="preview/browser"

    [trader-ui]="build"
    [tendies]="build"
    [visar]="build"
    [biomorph]="dist"
    [cashback]="dist"
    [cashback-deck]="dist"
    [cashback-biz]="dist"
)

# Systemd service name (node deploy type only, leave empty for static)
declare -A SERVICE_NAMES=(
    [lifevault]="lifevault"
    [ordretten]="ordretten"
    [roni]=""
    [ura]=""

    [trader-ui]="trader-ui"
    [tendies]="tendies"
    [visar]="visar"
    [biomorph]=""
    [cashback]=""
    [cashback-deck]=""
    [cashback-biz]=""
)

# Env file to copy from working dir before build (leave empty if not needed)
declare -A ENV_FILES=(
    [lifevault]=".env"
    [ordretten]=".env"
    [roni]=".env"
    [ura]=""

    [trader-ui]=".env"
    [tendies]=".env"
    [visar]=""
    [biomorph]=""
    [cashback]=""
    [cashback-deck]=""
    [cashback-biz]=""
)

# =============================================================================
# END CONFIG
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

record_build() {
    local status="$1"
    local duration="$2"
    local short_sha="${REMOTE_SHA:0:7}"
    local message
    message=$(git -C "$REPO_DIR" log -1 --format='%s' origin/main 2>/dev/null | head -c 120)
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    # Build JSON with jq to handle special characters in commit messages
    local json
    json=$(jq -cn \
        --arg p "$PROJECT" \
        --arg s "$status" \
        --arg sha "$short_sha" \
        --arg msg "$message" \
        --arg ts "$timestamp" \
        --argjson dur "$duration" \
        '{project:$p,status:$s,sha:$sha,message:$msg,timestamp:$ts,duration:$dur}')
    ssh "$SERVER" "cat >> /home/erdal/builds/builds.jsonl" <<< "$json" 2>/dev/null || true
    # Trim to last 200 entries
    ssh "$SERVER" "tail -200 /home/erdal/builds/builds.jsonl > /tmp/builds-trim.jsonl && mv /tmp/builds-trim.jsonl /home/erdal/builds/builds.jsonl" 2>/dev/null || true
}

# ---------- main ----------

PROJECT="${1:-}"
ALL_PROJECTS=$(echo "${!REPO_DIRS[@]}" | tr ' ' '|')
[[ -z "$PROJECT" ]] && die "Usage: $0 <$ALL_PROJECTS>"
[[ -z "${REPO_DIRS[$PROJECT]:-}" ]] && die "Unknown project: $PROJECT. Available: $ALL_PROJECTS"

REPO_DIR="$WORKSPACE/${REPO_DIRS[$PROJECT]}"
BUILD_DIR="$BUILD_BASE/$PROJECT"
SERVER_PATH="${SERVER_PATHS[$PROJECT]}"
DEPLOY_TYPE="${DEPLOY_TYPES[$PROJECT]}"
BUILD_OUTPUT="${BUILD_OUTPUTS[$PROJECT]}"
SERVICE="${SERVICE_NAMES[$PROJECT]:-}"
SHA_FILE="$DEPLOY_STATE_DIR/$PROJECT.sha"
LOG_FILE="$LOG_DIR/$PROJECT.log"

# 0. Per-project lock — prevent simultaneous deploys of the same project
DEPLOY_LOCK="/tmp/veron3-deploy-${PROJECT}.lock"
exec 200>"$DEPLOY_LOCK"
flock -n 200 || { log "$PROJECT: another deploy is already running — skipping"; exit 0; }

log "=== Deploying $PROJECT ===" | tee -a "$LOG_FILE"

# 1. Fetch latest from origin
log "Fetching origin/main..." | tee -a "$LOG_FILE"
git -C "$REPO_DIR" fetch origin main 2>>"$LOG_FILE" || die "git fetch failed"

# 2. Get current origin/main SHA
REMOTE_SHA=$(git -C "$REPO_DIR" rev-parse origin/main)
LAST_SHA=$(cat "$SHA_FILE" 2>/dev/null || echo "none")

if [[ "$REMOTE_SHA" == "$LAST_SHA" ]]; then
    log "$PROJECT: already at $REMOTE_SHA — skipping" | tee -a "$LOG_FILE"
    exit 0
fi

log "$PROJECT: $LAST_SHA → $REMOTE_SHA" | tee -a "$LOG_FILE"

# 3. Extract origin/main to a clean build directory (never touches working tree)
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
log "Extracting origin/main to $BUILD_DIR..." | tee -a "$LOG_FILE"
git -C "$REPO_DIR" archive origin/main | tar -x -C "$BUILD_DIR" 2>>"$LOG_FILE"

# Some tools (e.g. Astro MDX) call `git log` for file dates — init a temp repo
git -C "$BUILD_DIR" init -q 2>>"$LOG_FILE"
git -C "$BUILD_DIR" add -A 2>>"$LOG_FILE"
git -C "$BUILD_DIR" -c user.name="deploy" -c user.email="deploy@veron3" commit -qm "build $REMOTE_SHA" 2>>"$LOG_FILE"

# 4. Copy env file if needed (e.g. SvelteKit needs env vars at build time)
ENV_FILE="${ENV_FILES[$PROJECT]:-}"
if [[ -n "$ENV_FILE" && -f "$REPO_DIR/$ENV_FILE" ]]; then
    cp "$REPO_DIR/$ENV_FILE" "$BUILD_DIR/$ENV_FILE"
    log "Copied $ENV_FILE to build dir" | tee -a "$LOG_FILE"
fi

# 5. Restore cached node_modules if package-lock.json unchanged
LOCKFILE_HASH_FILE="$LOCKFILE_CACHE_DIR/$PROJECT.lockhash"
NODE_MODULES_CACHE="$BUILD_BASE/.nm-cache/$PROJECT"
BUILD_LOCKFILE="$BUILD_DIR/package-lock.json"

CACHE_HIT=false
CURRENT_HASH=""

if [[ -f "$BUILD_LOCKFILE" ]]; then
    CURRENT_HASH=$(md5sum "$BUILD_LOCKFILE" | cut -d' ' -f1)
    CACHED_HASH=$(cat "$LOCKFILE_HASH_FILE" 2>/dev/null || echo "none")
    CACHE_TARGET=$(dirname "$BUILD_LOCKFILE")/node_modules

    if [[ "$CURRENT_HASH" == "$CACHED_HASH" && -d "$NODE_MODULES_CACHE" ]]; then
        log "package-lock.json unchanged — restoring cached node_modules (skipping install)" | tee -a "$LOG_FILE"
        cp -a "$NODE_MODULES_CACHE" "$CACHE_TARGET"
        CACHE_HIT=true
    fi
fi

# 6. Install deps (skipped on cache hit) + Build
BUILD_START=$(date +%s)
if [[ "$CACHE_HIT" == "false" ]]; then
    log "Installing deps for $PROJECT..." | tee -a "$LOG_FILE"
    (cd "$BUILD_DIR" && eval "${INSTALL_CMDS[$PROJECT]}") >>"$LOG_FILE" 2>&1 || {
        log "INSTALL FAILED for $PROJECT — not deploying" | tee -a "$LOG_FILE"
        record_build "failure" "$(($(date +%s) - BUILD_START))"
        exit 1
    }
fi

log "Building $PROJECT..." | tee -a "$LOG_FILE"
(cd "$BUILD_DIR" && eval "${BUILD_CMDS[$PROJECT]}") >>"$LOG_FILE" 2>&1 || {
    log "BUILD FAILED for $PROJECT — not deploying" | tee -a "$LOG_FILE"
    record_build "failure" "$(($(date +%s) - BUILD_START))"
    exit 1
}

# Cache node_modules for next build
if [[ -f "$BUILD_LOCKFILE" ]]; then
    BUILT_MODULES=$(dirname "$BUILD_LOCKFILE")/node_modules
    if [[ -d "$BUILT_MODULES" ]]; then
        # Re-hash in case npm install created/updated the lockfile
        [[ -z "$CURRENT_HASH" ]] && CURRENT_HASH=$(md5sum "$BUILD_LOCKFILE" | cut -d' ' -f1)
        rm -rf "$NODE_MODULES_CACHE"
        mkdir -p "$(dirname "$NODE_MODULES_CACHE")"
        cp -a "$BUILT_MODULES" "$NODE_MODULES_CACHE"
        echo "$CURRENT_HASH" > "$LOCKFILE_HASH_FILE"
        log "Cached node_modules (lockfile hash: $CURRENT_HASH)" | tee -a "$LOG_FILE"
    fi
fi

# 7. Deploy to server
log "Deploying to $SERVER:$SERVER_PATH..." | tee -a "$LOG_FILE"

STAGING_PATH="${SERVER_PATH}.staging"

case "$DEPLOY_TYPE" in
    node)
        # Atomic deploy: rsync to staging dir, install deps, then swap + restart
        ssh "$SERVER" "rm -rf $STAGING_PATH && cp -a $SERVER_PATH $STAGING_PATH" 2>>"$LOG_FILE"
        rsync -az --delete "$BUILD_DIR/$BUILD_OUTPUT/" "$SERVER:$STAGING_PATH/$BUILD_OUTPUT/" 2>>"$LOG_FILE"
        rsync -az "$BUILD_DIR/package.json" "$BUILD_DIR/package-lock.json" "$SERVER:$STAGING_PATH/" 2>>"$LOG_FILE"
        ssh "$SERVER" "cd $STAGING_PATH && npm ci --production --ignore-scripts && sudo systemctl stop $SERVICE && rm -rf $SERVER_PATH && mv $STAGING_PATH $SERVER_PATH && sudo systemctl start $SERVICE" 2>>"$LOG_FILE" || {
            log "DEPLOY FAILED for $PROJECT on server" | tee -a "$LOG_FILE"
            # Try to restart the service with whatever is in place
            ssh "$SERVER" "sudo systemctl start $SERVICE" 2>/dev/null || true
            record_build "failure" "$(($(date +%s) - BUILD_START))"
            exit 1
        }
        ;;
    static)
        # Atomic deploy: rsync to staging dir, then swap
        ssh "$SERVER" "rm -rf $STAGING_PATH && mkdir -p $STAGING_PATH" 2>>"$LOG_FILE"
        rsync -az --delete "$BUILD_DIR/$BUILD_OUTPUT/" "$SERVER:$STAGING_PATH/" 2>>"$LOG_FILE"
        ssh "$SERVER" "rm -rf $SERVER_PATH && mv $STAGING_PATH $SERVER_PATH" 2>>"$LOG_FILE"
        ;;
    *)
        die "Unknown deploy type: $DEPLOY_TYPE"
        ;;
esac

# 8. Record deployed SHA and build result
echo "$REMOTE_SHA" > "$SHA_FILE"
record_build "success" "$(($(date +%s) - BUILD_START))"

SHORT_SHA="${REMOTE_SHA:0:7}"
COMMIT_MSG=$(git -C "$REPO_DIR" log -1 --format='%s' origin/main)
log "DEPLOYED $PROJECT @ $SHORT_SHA ($COMMIT_MSG)" | tee -a "$LOG_FILE"
