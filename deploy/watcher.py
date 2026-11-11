#!/usr/bin/env python3
"""Check GitHub heads in one persistent HTTPS request; deploy only changed SHAs.

The webhook remains the immediate push path. This independent 60s catch-up
check also catches remote pushes and missed webhooks, without Git worktree
scans or SSH/fetch subprocesses for unchanged projects. No third-party modules.
"""

import argparse
import fcntl
import http.client
import json
import os
from pathlib import Path
import re
import signal
import ssl
import subprocess
import threading
import time
from dataclasses import dataclass


SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?\Z")
GITHUB_REMOTE = re.compile(
    r"(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)"
    r"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?\Z"
)


def log(message):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}", flush=True)


def capture(args, timeout=30):
    """Bound metadata commands, including their SSH/credential helper children."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    env.setdefault("GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=10")
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, env=env, start_new_session=True) as process:
        try:
            stdout, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise RuntimeError("metadata command timed out") from None
    if process.returncode:
        # Do not log command output: remote URLs/credential errors can contain secrets.
        raise RuntimeError(f"metadata command exited {process.returncode}")
    return stdout.strip()


@dataclass(frozen=True)
class Project:
    name: str
    repo: Path
    state: Path

    def deployed_sha(self):
        try:
            return self.state.read_text().strip()
        except FileNotFoundError:
            return ""


def load_projects(script, names):
    # CI-managed projects are dispatched by the local CI timer.
    managed_file = Path.home() / ".local/share/hetzner-pc/config/ci-managed-projects.json"
    managed = json.loads(managed_file.read_text()) if managed_file.exists() else []
    if not isinstance(managed, list) or not all(isinstance(x, str) for x in managed):
        raise RuntimeError("Invalid CI handoff configuration")
    names = [name for name in names if name not in managed]
    config = capture([str(script), "--watch-config", *names])
    projects = []
    for row in config.splitlines():
        name, repo, state = row.split("\t")
        projects.append(Project(name, Path(repo).resolve(), Path(state)))
    return projects


class GitHubHeads:
    def __init__(self):
        self.connection = None
        self.token = None
        self.context = ssl.create_default_context()

    def close(self):
        if self.connection:
            self.connection.close()
            self.connection = None

    def heads(self, slugs):
        if not slugs:
            return {}
        if not self.token:
            self.token = capture(["gh", "auth", "token", "--hostname", "github.com"], timeout=10)
        fields = []
        for i, slug in enumerate(slugs):
            owner, name = slug.split("/")
            fields.append(
                f"r{i}:repository(owner:{json.dumps(owner)},name:{json.dumps(name)})"
                '{ref(qualifiedName:"refs/heads/main"){target{oid}}}'
            )
        body = json.dumps({"query": "{" + " ".join(fields) + "}"})
        try:
            # GitHub/proxies can close an idle keep-alive between checks. Retry
            # the read-only query on a fresh connection before falling back to
            # Git; otherwise every stale socket would launch all SSH checks.
            for attempt in range(2):
                try:
                    if self.connection is None:
                        self.connection = http.client.HTTPSConnection(
                            "api.github.com", timeout=20, context=self.context
                        )
                    self.connection.request("POST", "/graphql", body, {
                        "Authorization": "Bearer " + self.token,
                        "User-Agent": "veron3-deploy-watcher",
                        "Content-Type": "application/json",
                        "Accept": "application/vnd.github+json",
                    })
                    response = self.connection.getresponse()
                    raw = response.read()
                    if response.will_close:
                        self.close()
                    break
                except (OSError, http.client.HTTPException):
                    self.close()
                    if attempt:
                        raise
            if response.status != 200:
                if response.status == 401:
                    self.token = None  # Pick up a refreshed gh login on the next cycle.
                raise RuntimeError(f"GitHub HTTP {response.status}")
            data = json.loads(raw).get("data") or {}
            result = {}
            for i, slug in enumerate(slugs):
                repo = data.get(f"r{i}") or {}
                ref = repo.get("ref") or {}
                oid = (ref.get("target") or {}).get("oid", "")
                if SHA.fullmatch(oid):
                    result[slug] = oid
            return result
        except Exception:
            self.close()  # EOF, expired keep-alive, TLS/network error: reconnect next time.
            raise


class RemoteHeads:
    def __init__(self, github=None):
        self.github = github if github is not None else GitHubHeads()
        self.slugs = {}
        self.last_warning = None

    def heads(self, repos):
        for repo in repos:
            if repo not in self.slugs:
                try:
                    remote = capture(["git", "-C", str(repo), "remote", "get-url", "origin"])
                    match = GITHUB_REMOTE.fullmatch(remote)
                    self.slugs[repo] = match.group(1) if match else None
                except (OSError, RuntimeError):
                    # Retry missing/replaced repositories next cycle.
                    pass
        slugs = list(dict.fromkeys(s for s in self.slugs.values() if s))
        warnings = []
        try:
            github_heads = self.github.heads(slugs)
        except (OSError, RuntimeError, ValueError, http.client.HTTPException) as error:
            github_heads = {}
            warnings.append(f"GitHub batch unavailable ({type(error).__name__}); using Git head checks")
        result = {}
        for repo in repos:
            head = github_heads.get(self.slugs.get(repo))
            if head is None:
                warnings.append(f"Git head fallback for {repo.name}")
                # Retain auto-deploy when gh is missing/unauthorized, the API is
                # down, or a remote is not GitHub. One check per unique repo,
                # without fetch maintenance or working-tree scans.
                try:
                    output = capture(["git", "-C", str(repo), "ls-remote", "--exit-code",
                                      "origin", "refs/heads/main"])
                    head = output.split()[0]
                    if not SHA.fullmatch(head):
                        raise ValueError("invalid remote SHA")
                except (OSError, RuntimeError, ValueError, IndexError):
                    warnings.append(f"head unavailable for {repo.name}; will retry")
                    continue
            result[repo] = head
        warning = "; ".join(warnings)
        if warning != self.last_warning:
            if warning:
                log("WARNING: " + warning)
            elif self.last_warning:
                log("Remote head checks recovered")
            self.last_warning = warning
        return result


def check_projects(projects, heads, deploy_script, subdomain_script, run=subprocess.run, stop=None):
    pending = deployed = 0
    for project in projects:
        if stop is not None and stop.is_set():
            break
        head = heads.get(project.repo)
        if head is None:
            continue  # Never deploy from a stale/missing remote result.
        previous = project.deployed_sha()
        if previous == head:
            continue
        pending += 1
        log(f"{project.name}: remote main changed or deploy pending ({head[:12]})")
        result = run([str(deploy_script), project.name], check=False)
        current = project.deployed_sha()
        if result.returncode != 0 or not current or current == previous:
            # deploy.sh can exit 0 when another deploy owns its per-project
            # flock. Keep checking the state rather than acknowledging a skip.
            log(f"WARNING: {project.name} still pending; will retry next cycle")
            continue
        deployed += 1
        if project.name == "admin" and (stop is None or not stop.is_set()):
            run([str(subdomain_script)], check=False)
    return pending, deployed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval", type=float, default=60)
    parser.add_argument("--once", action="store_true", help="check once (may deploy)")
    parser.add_argument("projects", nargs="+")
    args = parser.parse_args()
    if args.interval <= 0:
        parser.error("--interval must be positive")
    script_dir = Path(__file__).resolve().parent
    # Dedicated lifetime flock; closing/crashing releases it without stale PID
    # files. deploy.sh's separate per-project locks still coordinate webhooks.
    lock_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    with (lock_dir / "veron3-deploy-watcher.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log("Another watcher is already running")
            return
        projects = load_projects(script_dir / "deploy.sh", args.projects)
        repos = list(dict.fromkeys(p.repo for p in projects))
        remote = RemoteHeads()
        log(f"veron3-deploy watcher started ({len(projects)} projects, {len(repos)} repos; "
            f"batched remote heads every {args.interval:g}s)")
        stop = threading.Event()
        signal.signal(signal.SIGTERM, lambda *_: stop.set())
        signal.signal(signal.SIGINT, lambda *_: stop.set())
        try:
            while not stop.is_set():
                heads = remote.heads(repos)
                if stop.is_set():
                    break
                pending, deployed = check_projects(
                    projects, heads, script_dir / "deploy.sh", script_dir / "check-subdomains.sh",
                    stop=stop
                )
                log(f"Head check: {len(heads)}/{len(repos)} repos, "
                    f"{pending} pending, {deployed} deployed")
                if args.once:
                    break
                stop.wait(args.interval)  # Blocking wait: no sleep subprocess/poll loop.
        finally:
            remote.github.close()


if __name__ == "__main__":
    main()
