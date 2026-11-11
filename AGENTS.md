# veron3 Hetzner

Before deploys read /home/visar/Documents/environment/services/hetzner-pc/README.md
for authoritative per-project services/data, ../CREDENTIALS.md on demand and deploy/.
SSH: ssh erdal@157.90.28.14; Caddy: /etc/caddy/Caddyfile. Check each project's
publisher: main pushes trigger its configured watcher/webhook or dedicated CI.

Returned production projects must serve/authenticate/store data/run workers and
local backups without the PC. PC off-server backup fetches may remain. Restore
current authoritative state, never frozen migration copies. Preserve functionality
and unrelated data; no blanket service/authentication resets. Required recovery
survives reboot without an agent/helper.

“Move this, then circle back” preserves and resumes the unfinished repair.
Children need exact project/destination, topology/data owner, deployment authority,
resource/device limits, validation and delivery criteria; no inherited history.
