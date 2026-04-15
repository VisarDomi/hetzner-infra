# veron3 auto-deploy

Push to `main` on any configured project → deployed to Hetzner within ~2 minutes.

Visar's local PC (z440) is the build server. `veron3-deploy.service` polls GitHub every 60s, builds from `origin/main` via `git archive` (never touches working tree), and deploys via rsync. `veron3-webhook.service` runs the local GitHub webhook receiver for immediate push-triggered deploys.

## Quick reference

```bash
./deploy/status.sh                                    # what's deployed
journalctl --user -u veron3-deploy.service -f         # live logs
systemctl --user restart veron3-deploy.service        # restart watcher
journalctl --user -u veron3-webhook.service -f        # webhook logs
systemctl --user restart veron3-webhook.service       # restart webhook receiver
./deploy/deploy.sh <project>                          # manual deploy
```

## Adding a new project

Three steps. Takes ~5 minutes.

### Step 1: Add config to deploy.sh

Open `deploy/deploy.sh` and add one entry to each config array in the `PROJECT CONFIGURATION` section:

```bash
# Example: adding a new project called "myapp"

declare -A REPO_DIRS=(
    ...existing...
    [myapp]="my-app-repo"            # directory name under /home/visar/Documents/work/hetzner/
)

declare -A SERVER_PATHS=(
    ...existing...
    [myapp]="/home/erdal/myapp"      # where files go on the server
)

declare -A DEPLOY_TYPES=(
    ...existing...
    [myapp]="static"                 # "static" or "node"
)

declare -A BUILD_CMDS=(
    ...existing...
    [myapp]="npm ci && npm run build"  # build command (runs in extracted source dir)
)

declare -A BUILD_OUTPUTS=(
    ...existing...
    [myapp]="dist"                   # where build output lives (relative to project root)
)

declare -A SERVICE_NAMES=(
    ...existing...
    [myapp]=""                       # systemd service name (only for "node" type, empty for static)
)

declare -A ENV_FILES=(
    ...existing...
    [myapp]=""                       # .env file needed at build time (empty if not needed)
)
```

**Deploy types:**
- `static` — rsync build output to server path. No restart needed. (SPAs, Astro, static sites)
- `node` — rsync build output + package.json, run `npm ci --production` on server, restart systemd service. (SvelteKit, Express, etc.)

### Step 2: Add to watcher

Open `deploy/watcher.sh` and add the project name to the `PROJECTS` array:

```bash
PROJECTS=(lifevault ordretten roni ura astronews myapp)
```

### Step 3: Ensure server directory exists

```bash
ssh erdal@157.90.28.14 "mkdir -p /home/erdal/myapp"
```

For Node apps, you also need a systemd service on the server:

```bash
ssh erdal@157.90.28.14 "sudo tee /etc/systemd/system/myapp.service" << 'EOF'
[Unit]
Description=myapp
After=network.target

[Service]
Type=simple
User=erdal
WorkingDirectory=/home/erdal/myapp
ExecStart=/usr/bin/node build
Restart=on-failure
RestartSec=5
EnvironmentFile=/home/erdal/myapp/.env

[Install]
WantedBy=multi-user.target
EOF

ssh erdal@157.90.28.14 "sudo systemctl daemon-reload && sudo systemctl enable myapp"
```

For static sites, add a Caddy block in `/etc/caddy/Caddyfile`:

```
myapp.veron3.space {
    root * /home/erdal/myapp
    file_server
    try_files {path} /index.html
}
```

Then `ssh erdal@157.90.28.14 "sudo systemctl reload caddy"`.

### Step 4: Restart watcher

```bash
systemctl --user restart veron3-deploy.service
```

The watcher will immediately detect the new project has no deployed SHA and deploy it.

### Step 5: Verify

```bash
./deploy/status.sh
```

## Repos outside the workspace

Some projects live outside the deploy workspace (`/home/visar/Documents/work/hetzner/`). These need symlinks so the deploy script can find them. After cloning on a fresh machine, recreate these:

```bash
ln -s /home/visar/Documents/work/trading/trader /home/visar/Documents/work/hetzner/trader-ui
ln -s /home/visar/Documents/work/trading/trader-svelte /home/visar/Documents/work/hetzner/trader-svelte
```

If a project's `REPO_DIRS` entry points to a directory that doesn't exist directly under the workspace, check whether it lives in another repo directory (e.g. `trading-repos/`, `manga-repos/`) and create a symlink.

## How it works

```
 You push to main
       │
       ▼
 GitHub (origin/main)
       │
       │  git fetch (every 60s from Visar's PC)
       ▼
 SHA changed? ──no──▶ skip
       │
      yes
       │
       ▼
 git archive origin/main ──▶ /tmp/veron3-build/<project>/
       │
       ▼
 npm ci && npm run build
       │
   build ok? ──no──▶ log error, server keeps running old version
       │
      yes
       │
       ▼
 rsync to erdal@157.90.28.14:/home/erdal/<project>/
       │
       ▼
 (node only) npm ci --production && systemctl restart <service>
       │
       ▼
 Save SHA to deploy/.state/<project>.sha
```

## Troubleshooting

**Build fails**: Check `deploy/logs/<project>.log` for the full build output.

**Service won't restart**: SSH to server and check `journalctl -u <service> -n 50`.

**Watcher not running**: `systemctl --user status veron3-deploy.service`. If dead, check `journalctl --user -u veron3-deploy.service -n 100`.

**Force redeploy**: Delete the state file and restart: `rm deploy/.state/<project>.sha && systemctl --user restart veron3-deploy.service`

**PC rebooted**: The service auto-starts (linger enabled). It catches up on all missed deploys on the first cycle.
