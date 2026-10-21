"""Safe watcher regression checks: temporary Git remotes and fake deploy handlers."""

import http.client
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location("veron3_watcher", Path(__file__).parents[1] / "watcher.py")
watcher = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = watcher
SPEC.loader.exec_module(watcher)


class FixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        self.origin = self.root / "origin.git"
        self.git("init", "--bare", "--initial-branch=main", str(self.origin))
        self.git("init", "--initial-branch=main", str(self.repo))
        self.git("-C", str(self.repo), "config", "user.name", "Fixture")
        self.git("-C", str(self.repo), "config", "user.email", "fixture@localhost")
        self.git("-C", str(self.repo), "remote", "add", "origin", str(self.origin))
        self.first = self.push_commit("first")
        self.projects = [watcher.Project(name, self.repo, self.root / f"{name}.sha")
                         for name in ("app", "showcase")]
        for project in self.projects:
            project.state.write_text(self.first + "\n")
        self.calls = self.root / "calls.jsonl"
        self.deploy = self.root / "deploy-fixture.py"
        self.deploy.write_text('''#!/usr/bin/env python3
import json, pathlib, subprocess, sys
root = pathlib.Path(__file__).parent
project = sys.argv[1]
with (root / "calls.jsonl").open("a") as output:
    output.write(json.dumps(project) + "\\n")
failure = root / "fail-once"
if failure.exists():
    failure.unlink()
    sys.exit(1)
head = subprocess.check_output(["git", "-C", str(root / "source"), "ls-remote",
                                "origin", "refs/heads/main"], text=True).split()[0]
(root / (project + ".sha")).write_text(head + "\\n")
''')
        self.deploy.chmod(0o700)
        self.audit = self.root / "audit-fixture.sh"
        self.audit.write_text('#!/bin/sh\nprintf "audit\\n" >> "$(dirname "$0")/audits"\n')
        self.audit.chmod(0o700)
        # A non-GitHub local remote intentionally uses the real Git fallback.
        self.remote = watcher.RemoteHeads(github=Mock(heads=Mock(return_value={})))

    def git(self, *args):
        return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL, text=True).strip()

    def push_commit(self, text):
        (self.repo / "app.txt").write_text(text)
        self.git("-C", str(self.repo), "add", "app.txt")
        self.git("-C", str(self.repo), "commit", "-m", text)
        self.git("-C", str(self.repo), "push", "origin", "main")
        return self.git("-C", str(self.repo), "rev-parse", "HEAD")

    def tick(self, projects=None):
        projects = self.projects if projects is None else projects
        heads = self.remote.heads(list(dict.fromkeys(p.repo for p in projects)))
        return watcher.check_projects(projects, heads, self.deploy, self.audit)

    def test_remote_push_fans_out_and_unchanged_cycles_do_nothing(self):
        self.assertEqual(self.tick(), (0, 0))
        self.assertFalse(self.calls.exists())
        second = self.push_commit("new remote main")
        # Local origin/main is deliberately stale: the remote check must still
        # discover pushes without relying on local working-tree/ref events.
        self.git("-C", str(self.repo), "update-ref", "refs/remotes/origin/main", self.first)
        self.assertEqual(self.tick(), (2, 2))
        self.assertEqual([p.deployed_sha() for p in self.projects], [second, second])
        self.assertEqual(self.tick(), (0, 0))
        self.assertEqual(self.calls.read_text().splitlines(), ['"app"', '"showcase"'])
        self.assertFalse((self.root / "audits").exists())

    def test_failed_deploy_retries_without_acknowledging_sha(self):
        second = self.push_commit("retry")
        (self.root / "fail-once").touch()
        self.assertEqual(self.tick(self.projects[:1]), (1, 0))
        self.assertEqual(self.projects[0].deployed_sha(), self.first)
        self.assertEqual(self.tick(self.projects[:1]), (1, 1))
        self.assertEqual(self.projects[0].deployed_sha(), second)
        self.assertEqual(self.tick(self.projects[:1]), (0, 0))

    def test_per_project_lock_skip_is_retried(self):
        self.push_commit("lock busy")
        heads = self.remote.heads([self.repo])
        run = Mock(return_value=subprocess.CompletedProcess([], 0))
        for _ in range(2):
            self.assertEqual(watcher.check_projects(self.projects[:1], heads,
                                                   self.deploy, self.audit, run), (1, 0))
        self.assertEqual(run.call_count, 2)
        self.assertEqual(self.projects[0].deployed_sha(), self.first)

    def test_missing_remote_result_never_deploys_stale_ref(self):
        self.projects[0].state.unlink()
        run = Mock()
        self.assertEqual(watcher.check_projects(self.projects, {}, self.deploy,
                                               self.audit, run), (0, 0))
        run.assert_not_called()

    def test_shutdown_does_not_start_other_pending_deploys(self):
        self.push_commit("pending at shutdown")
        heads = self.remote.heads([self.repo])
        stop = threading.Event()

        def stopped_child(*args, **kwargs):
            stop.set()
            return subprocess.CompletedProcess([], -15)

        run = Mock(side_effect=stopped_child)
        self.assertEqual(watcher.check_projects(self.projects, heads, self.deploy,
                                               self.audit, run, stop), (1, 0))
        run.assert_called_once()

    def test_deleted_state_redeploys_and_admin_audit_runs_only_after_change(self):
        admin = watcher.Project("admin", self.repo, self.root / "admin.sha")
        admin.state.write_text(self.first)
        self.assertEqual(self.tick([admin]), (0, 0))
        self.assertFalse((self.root / "audits").exists())
        admin.state.unlink()
        self.assertEqual(self.tick([admin]), (1, 1))
        self.assertEqual(self.tick([admin]), (0, 0))
        self.assertEqual((self.root / "audits").read_text(), "audit\n")


class MetadataTests(unittest.TestCase):
    def test_one_api_batch_and_no_git_commands_on_unchanged_cycles(self):
        github = Mock()
        github.heads.return_value = {"Owner/repo": "a" * 40}
        remote = watcher.RemoteHeads(github)
        repo = Path("/fixture/repo")
        with patch.object(watcher, "capture", return_value="git@github.com:Owner/repo.git") as capture:
            for _ in range(3):
                self.assertEqual(remote.heads([repo]), {repo: "a" * 40})
            self.assertEqual(capture.call_count, 1)  # Startup config only.
        self.assertEqual(github.heads.call_count, 3)
        github.heads.assert_called_with(["Owner/repo"])

    def test_api_failure_falls_back_then_recovers(self):
        github = Mock()
        github.heads.side_effect = [OSError("offline"), {"Owner/repo": "b" * 40}]
        remote = watcher.RemoteHeads(github)
        repo = Path("/fixture/repo")
        with patch.object(watcher, "capture", side_effect=[
            "https://github.com/Owner/repo.git", "a" * 40 + "\trefs/heads/main"
        ]) as capture:
            self.assertEqual(remote.heads([repo]), {repo: "a" * 40})
            self.assertEqual(remote.heads([repo]), {repo: "b" * 40})
            self.assertEqual(capture.call_count, 2)

    def test_partial_api_access_falls_back_only_for_unavailable_repo(self):
        github = Mock()
        github.heads.return_value = {"Owner/one": "a" * 40}
        remote = watcher.RemoteHeads(github)
        one, two = Path("/fixture/one"), Path("/fixture/two")
        with patch.object(watcher, "capture", side_effect=[
            "git@github.com:Owner/one.git", "git@github.com:Other/two.git",
            "b" * 40 + "\trefs/heads/main"
        ]) as capture:
            self.assertEqual(remote.heads([one, two]), {one: "a" * 40, two: "b" * 40})
            self.assertEqual(capture.call_count, 3)

    @staticmethod
    def response(status=200):
        response = Mock(status=status, will_close=False)
        response.read.return_value = json.dumps({
            "data": {"r0": {"ref": {"target": {"oid": "a" * 40}}}}
        }).encode()
        return response

    def test_expired_keepalive_reconnects_before_git_fallback(self):
        client = watcher.GitHubHeads()
        client.token = "fixture-only"
        first, fresh = Mock(), Mock()
        first.request.side_effect = [None, http.client.RemoteDisconnected()]
        first.getresponse.return_value = self.response()
        fresh.getresponse.return_value = self.response()
        with patch.object(watcher.http.client, "HTTPSConnection", side_effect=[first, fresh]) as connect:
            self.assertEqual(client.heads(["Owner/repo"]), {"Owner/repo": "a" * 40})
            self.assertEqual(client.heads(["Owner/repo"]), {"Owner/repo": "a" * 40})
            self.assertEqual(connect.call_count, 2)
        first.close.assert_called_once()

    def test_unauthorized_token_is_reloaded(self):
        client = watcher.GitHubHeads()
        client.token = "expired-fixture-only"
        connection = Mock()
        connection.getresponse.side_effect = [self.response(401), self.response()]
        with patch.object(watcher.http.client, "HTTPSConnection", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "GitHub HTTP 401"):
                client.heads(["Owner/repo"])
            self.assertIsNone(client.token)
            with patch.object(watcher, "capture", return_value="refreshed-fixture-only") as capture:
                self.assertEqual(client.heads(["Owner/repo"]), {"Owner/repo": "a" * 40})
                capture.assert_called_once()


if __name__ == "__main__":
    unittest.main()
