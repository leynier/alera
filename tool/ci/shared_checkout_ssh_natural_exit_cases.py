"""Close and restart retained Home tabs after a verified natural owner exit."""

import base64
import hashlib
import shlex
import sqlite3
import time
import uuid


def verify_natural_exit(root, cli, workspace, rpc):
    profile = hashlib.sha256(workspace["projectId"].encode()).hexdigest()
    owner_state = root / "fixture-sidecar" / "owners" / profile
    for action in ("close", "restart"):
        marker = root / f"natural-{action}.txt"
        tab = cli("tab", [
            "create", "--workspace-id", workspace["id"], "--title", "Natural exit",
            "--spawn", "--command", f"printf 'exited\\n' > {shlex.quote(str(marker))}; exit",
        ])
        session_id = tab["payload"]["terminalSessionId"]
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            with sqlite3.connect(f"file:{owner_state}/runtime.sqlite?mode=ro", uri=True) as database:
                receipt = database.execute("SELECT closed FROM terminalLifecycleOperations WHERE sessionId = ? AND json_extract(recordJson, '$.initiatorEpoch') LIKE 'natural-exit:%'", (session_id,)).fetchone()
            with sqlite3.connect(f"file:{root}/home-state/terminal_history.sqlite?mode=ro", uri=True) as database:
                checkpoint = database.execute("SELECT running FROM checkpoints WHERE sessionId = ?", (session_id,)).fetchone()
            if marker.exists() and receipt == (1,) and checkpoint == (0,):
                break
            time.sleep(0.1)
        else:
            raise AssertionError("Natural owner exit did not retain verified closure evidence")
        if action == "close":
            cli("tab", ["remove", "--id", tab["id"]])
        else:
            rpc("terminal.restart", {
                "operationId": str(uuid.uuid4()), "sessionId": session_id,
                "tabId": tab["id"], "workspaceId": workspace["id"],
                "workingDirectory": workspace["path"], "cols": 100, "rows": 30,
                "launch": {"label": "Fixture", "shell": "/bin/sh", "arguments": [], "environment": {}},
            })
            restarted = root / "natural-restarted.txt"
            command = f"printf 'restarted\\n' > {shlex.quote(str(restarted))}\n"
            rpc("write", {"sessionId": session_id, "dataBase64": base64.b64encode(command.encode()).decode()})
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if restarted.exists() and restarted.read_text() == "restarted\n":
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Natural-exit restart did not create a usable owner terminal")
            rpc("terminate", {"sessionId": session_id})
    print("Natural SSH owner exit retained evidence for Close and Restart", flush=True)
    return {"home_natural_owner_exit_close": True, "home_natural_owner_exit_restart": True}
