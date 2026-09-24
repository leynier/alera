"""Real owner precheck cancellation and recovery in the isolated SSH fixture."""

import datetime
import hashlib
import json
import os
import pathlib
import shlex
import signal
import sqlite3
import time
import uuid


def wait_for(predicate, label, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {label}")


def identity(pid):
    try:
        fields = pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
        return fields[19], fields[0]
    except FileNotFoundError:
        return None


def alive(process):
    current = identity(process[0])
    return current is not None and current[0] == process[1] and current[1] != "Z"


def evidence(state, run_id):
    with sqlite3.connect(f"file:{state}/runtime.sqlite?mode=ro", uri=True) as database:
        rows = database.execute("SELECT recordJson FROM automationPrecheckProcesses WHERE runId = ?", (run_id,)).fetchall()
    return [json.loads(row[0]) for row in rows]


def verify_prechecks(root, cli, rpc, restart_home):
    profile = rpc("agentProfile.upsert", {
        "name": "Precheck Fixture", "agentType": "codex", "launchMode": "command",
        "command": "/usr/bin/false",
    })
    rpc("automation.policy", {"kind": "agent", "profileId": profile["id"], "policy": {"mayExecute": True}})
    results = {}
    runs = []
    processes = []
    try:
        for scenario in ("lost-response", "timeout", "home-restart", "linked", "linked-lost-response", "linked-home-restart", "legacy-linked"):
            lost_response = scenario.endswith("lost-response")
            home_restart = scenario.endswith("home-restart")
            task = None
            principal = None
            if scenario == "legacy-linked":
                from shared_checkout_ssh_linked_precheck_cases import prepare_legacy_linked_precheck
                project, remote, task, principal = prepare_legacy_linked_precheck(root, cli, rpc)
                retained = remote / "retained.txt"
            elif scenario.startswith("linked"):
                from shared_checkout_ssh_linked_precheck_cases import prepare_linked_precheck
                project, remote, task, principal = prepare_linked_precheck(root, cli, scenario)
                retained = remote / "retained.txt"
            else:
                local = root / f"precheck-{scenario}-local"
                remote = root / f"precheck-{scenario}-remote"
                local.mkdir()
                remote.mkdir()
                (remote / "alera.toml").write_text("[automation]\ndeclared = true\n")
                retained = remote / "retained.txt"
                retained.write_text("shared fixture content\n")
                project = cli("project", ["add", "--name", f"Precheck {scenario}", "--repo-path", str(local), "--kind", "folder"])["project"]
                for initial_task in cli("workspace", ["list", "--project-id", project["id"]])["items"]:
                    cli("workspace", ["remove", "--id", initial_task["id"], "--close-sessions", "--keep-branch"])
                cli("project", ["register-checkout", "--project-id", project["id"], "--host-id", "fixture-ssh", "--path", str(remote)])
            expected_tasks = [] if task is None else [task["id"]]
            marker = remote / "count.txt"
            root_pid = remote / "root.pid"
            child_pid = remote / "child.pid"
            command = (
                f"printf x >> {shlex.quote(str(marker))}; echo $$ > {shlex.quote(str(root_pid))}; "
                f"/usr/bin/sleep 120 & echo $! > {shlex.quote(str(child_pid))}; wait"
            )
            now = datetime.datetime.now(datetime.UTC)
            actor = {"kind": "localCli"}
            definition = rpc("automation.upsert", {"automation": {
                "id": str(uuid.uuid4()), "slug": f"precheck-{scenario}", "name": f"Precheck {scenario}",
                "promptTemplate": "Isolated fixture, never dispatch an agent",
                "schedule": {"oneTime": {"at": (now + datetime.timedelta(days=1)).isoformat(), "timezone": "UTC"}},
                "target": ({"projectCheckout": {"projectId": project["id"], "hostId": "fixture-ssh", "agentProfileId": profile["id"]}}
                    if task is None else {"freshTab": {"workspaceId": task["id"], "agentProfileId": profile["id"]}}),
                "state": "draft", "revision": 0, "createdBy": actor, "modifiedBy": actor,
                "createdAt": now.isoformat(), "updatedAt": now.isoformat(),
                "precheck": {"command": command, "timeoutSeconds": 3 if scenario == "timeout" else 90},
            }})
            starts_log = root / "owner-precheck-starts.log"
            starts_before = len(starts_log.read_text().splitlines()) if starts_log.exists() else 0
            if lost_response:
                (root / "lose-next-owner-precheck-response").touch()
            run = rpc("automation.runNow", {"id": definition["id"], "draftTest": True, "precheck": True, "overlap": "skip"})
            runs.append((run["id"], run["targetIdentity"]))
            wait_for(lambda: root_pid.exists() and child_pid.exists(), f"{scenario} native command")
            current_processes = []
            for path in (root_pid, child_pid):
                pid = int(path.read_text().strip())
                current = identity(pid)
                assert current is not None and current[1] != "Z", f"Fixture process exited before observation: {path}"
                current_processes.append((pid, current[0]))
            processes.extend(current_processes)
            assert [item["id"] for item in cli("workspace", ["list", "--project-id", project["id"]])["items"]] == expected_tasks
            assert marker.read_text() == "x", "A precheck command was duplicated"
            records = evidence(root / "home-state", run["id"])
            assert len(records) == 1 and records[0]["phase"] == "launchIntent", records
            if task is not None:
                try:
                    cli("workspace", ["remove", "--id", task["id"], "--close-sessions", "--keep-branch"])
                except RuntimeError as error:
                    assert any(word in str(error).lower() for word in ("automation", "precheck")), str(error)
                else:
                    raise AssertionError("An active linked precheck allowed workspace retirement")
                assert remote.exists() and retained.read_text() == "shared fixture content\n"
            if lost_response:
                wait_for(lambda: not (root / "lose-next-owner-precheck-response").exists(), "lost response injection")
                wait_for(lambda: (root / "owner-precheck-starts.log").exists() and len((root / "owner-precheck-starts.log").read_text().splitlines()) >= starts_before + 2, "same-operation Start retry")
            if home_restart:
                starts_before_restart = (root / "owner-precheck-starts.log").read_text()
                restart_home()
                assert all(alive(process) for process in current_processes), "Home shutdown killed the owner command"
                wait_for(lambda: rpc("automation.runShow", {"id": run["id"]})["run"]["status"] in ("dispatching", "waitingForUser"), "Home recovery")
            if scenario != "timeout":
                cancellation_started = time.monotonic()
                rpc("automation.cancel", {"run": run["id"], "targetIdentity": run["targetIdentity"]})
            expected = "precheckSkipped" if scenario == "timeout" else "cancelled"

            def finished_run():
                shown = rpc("automation.runShow", {"id": run["id"]})["run"]
                return shown if shown["status"] == expected else None

            # Recovery uses the existing scheduler's 60-second idle tick.
            final = wait_for(finished_run, f"{scenario} final run", 90 if home_restart else 45)
            wait_for(lambda: not any(alive(process) for process in current_processes), f"{scenario} process closure")
            assert final["attemptCount"] == 0
            assert evidence(root / "home-state", run["id"])[0]["phase"] == "closureVerified"
            owner = root / "fixture-sidecar" / "owners" / hashlib.sha256(project["id"].encode()).hexdigest()
            with sqlite3.connect(f"file:{owner}/runtime.sqlite?mode=ro", uri=True) as database:
                rows = database.execute("SELECT requestJson, resultJson, processId FROM ownerAutomationPrechecks").fetchall()
                assert len(rows) == 1, rows
                request, result, process_id = rows[0]
                assert json.loads(request)["operationId"] == records[0]["id"]
                assert json.loads(result)["kind"] == ("timedOut" if scenario == "timeout" else "cancelled")
                native = json.loads(database.execute("SELECT recordJson FROM automationPrecheckProcesses WHERE id = ?", (process_id,)).fetchone()[0])
                assert native["phase"] == "closureVerified"
                assert database.execute("SELECT COUNT(*) FROM workspaces").fetchone()[0] == len(expected_tasks)
                if task is not None:
                    scope = json.loads(request)["workspace"]
                    assert scope["workspaceId"] == task["id"] and scope["instanceId"] == task["instanceId"]
                    assert scope["repositoryPath"] == str(principal)
                    assert native["workspace"] == scope
                    if scenario == "legacy-linked":
                        assert database.execute("SELECT COUNT(*) FROM repositoryCheckouts WHERE kind = 'project'").fetchone()[0] == 0
            if scenario == "legacy-linked":
                with sqlite3.connect(f"file:{root}/home-state/runtime.sqlite?mode=ro", uri=True) as database:
                    assert database.execute("SELECT COUNT(*) FROM repositoryCheckouts WHERE projectId = ? AND hostId = 'fixture-ssh' AND kind = 'project'", (project["id"],)).fetchone()[0] == 0
                    assert database.execute("SELECT c.repositoryPath FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b ON b.checkoutId = c.id WHERE b.workspaceId = ?", (task["id"],)).fetchone()[0] == str(principal)
            assert marker.read_text() == "x"
            assert retained.read_text() == "shared fixture content\n"
            assert [item["id"] for item in cli("workspace", ["list", "--project-id", project["id"]])["items"]] == expected_tasks
            if home_restart:
                assert (root / "owner-precheck-starts.log").read_text() == starts_before_restart
                results[f"ssh_precheck_{scenario.replace('-', '_')}_cancel_seconds"] = round(time.monotonic() - cancellation_started, 2)
            results[f"ssh_precheck_{scenario.replace('-', '_')}"] = True
            print(f"SSH precheck {scenario}: one command, verified closure, {len(expected_tasks)} retained tasks", flush=True)
        return results
    finally:
        for run_id, target in runs:
            try:
                cli("automation", ["cancel", "--run", run_id, "--profile-id", target["profileId"]])
            except (RuntimeError, OSError):
                pass
        for process in processes:
            if alive(process):
                os.kill(process[0], signal.SIGKILL)
        wait_for(lambda: not any(alive(process) for process in processes), "fixture precheck cleanup", 10)
