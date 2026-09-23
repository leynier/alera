"""Recover a Home tab after its initial SSH transport fails before enrollment."""

import base64
import hashlib
import shlex
import sqlite3
import time
import uuid


def verify_initial_failure(root, cli, rpc):
    results = {}
    for action in ("close", "restart"):
        local = root / f"initial-{action}-local"
        remote = root / f"initial-{action}-remote"
        local.mkdir()
        remote.mkdir()
        retained = remote / "retained.txt"
        retained.write_text("shared files\n")
        created = cli("project", ["add", "--name", f"Initial {action}", "--repo-path", str(local), "--kind", "folder"])
        project = created.get("project", created)
        cli("project", ["register-checkout", "--project-id", project["id"],
                        "--host-id", "fixture-ssh", "--path", str(remote)])
        created = cli("workspace", ["add", "--project-id", project["id"],
                                    "--host-id", "fixture-ssh"])
        workspace = created.get("workspace", created)
        profile = hashlib.sha256(project["id"].encode()).hexdigest()
        owner = root / "fixture-sidecar" / "owners" / profile
        assert not owner.exists(), "The recovery fixture already has an owner"
        failure = root / "fail-next-owner-terminal"
        failure.touch()
        tab = cli("tab", ["create", "--workspace-id", workspace["id"],
                          "--title", "Initial SSH Failure", "--spawn"])
        session = tab["payload"]["terminalSessionId"]
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            with sqlite3.connect(f"file:{root}/home-state/terminal_history.sqlite?mode=ro", uri=True) as database:
                checkpoint = database.execute("SELECT running FROM checkpoints WHERE sessionId = ?", (session,)).fetchone()
            if not failure.exists() and checkpoint == (0,):
                break
            time.sleep(0.1)
        else:
            raise AssertionError("The initial transport did not exit as expected")
        assert not owner.exists(), "The failed initial transport reached an owner"
        if action == "close":
            cli("tab", ["remove", "--id", tab["id"]])
        else:
            rpc("terminal.restart", {
                "operationId": str(uuid.uuid4()), "sessionId": session,
                "tabId": tab["id"], "workspaceId": workspace["id"],
                "workingDirectory": workspace["path"], "cols": 100, "rows": 30,
                "launch": {"label": "Fixture", "shell": "/bin/sh", "arguments": [], "environment": {}},
            })
            marker = remote / "restarted.txt"
            command = f"printf 'recovered\\n' > {shlex.quote(str(marker))}\n"
            rpc("write", {"sessionId": session, "dataBase64": base64.b64encode(command.encode()).decode()})
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if marker.exists() and marker.read_text() == "recovered\n":
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("The replacement owner terminal did not execute a command")
            rpc("terminate", {"sessionId": session})
        tasks = cli("workspace", ["list", "--project-id", project["id"]])["items"]
        current = next(task for task in tasks if task["id"] == workspace["id"])
        assert current["instanceId"] == workspace["instanceId"]
        assert retained.read_text() == "shared files\n"
        assert len(tasks) == 2, "Recovery changed neighboring task records"
        results[f"home_initial_ssh_failure_{action}"] = True
    print("Initial SSH transport failure recovered through Close and Restart", flush=True)
    return results
