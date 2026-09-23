"""Explicit Home terminal closure against a real loopback SSH owner."""

import base64
import json
import socket
import sqlite3
import shlex
import time
import uuid
from pathlib import Path

from shared_checkout_ssh_natural_exit_cases import verify_natural_exit


def verify_terminal_close(root, cli, workspace, rpc):
    results = verify_natural_exit(root, cli, workspace, rpc)
    for action in ("terminate", "tab-remove", "restart", "restart-lost-response", "restart-completed-replay"):
        results.update(_verify_action(root, cli, workspace, rpc, action))
    return results


def _verify_action(root, cli, workspace, rpc, action):
    marker = root / f"explicit-{action}-child.pid"
    tab = cli(
        "tab",
        [
            "create", "--workspace-id", workspace["id"], "--title", "Close child",
            "--spawn", "--command",
            f"sleep 600 & child=$!; printf '%s\\n' \"$child\" > {shlex.quote(str(marker))}; wait",
        ],
    )
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if marker.exists() and marker.read_text().strip():
            break
        time.sleep(0.1)
    else:
        raise AssertionError("The terminal owner did not start its fixture child")
    child = int(marker.read_text())
    proc = Path(f"/proc/{child}/stat")
    identity = proc.read_text().rsplit(")", 1)[1].split()[19]
    session_id = tab["payload"]["terminalSessionId"]
    if action == "tab-remove":
        cli("tab", ["remove", "--id", tab["id"]])
    elif action.startswith("restart"):
        restart_payload = {
            "operationId": str(uuid.uuid4()),
            "sessionId": session_id, "tabId": tab["id"],
            "workspaceId": workspace["id"], "workingDirectory": workspace["path"],
            "cols": 100, "rows": 30,
            "launch": {"label": "Fixture", "shell": "/bin/sh", "arguments": [], "environment": {}},
        }
        if action == "restart-lost-response":
            _drop_restart_response(root, restart_payload)
        rpc("terminal.restart", restart_payload)
        if action == "restart-lost-response":
            with sqlite3.connect(f"file:{root}/home-state/runtime.sqlite?mode=ro", uri=True) as database:
                count = database.execute("SELECT count(*) FROM terminalLifecycleOperations WHERE sessionId = ?", (session_id,)).fetchone()[0]
            assert count == 1, "Lost-response retry dispatched a second owner action"
    else:
        rpc("terminate", {"sessionId": session_id})
    if proc.exists():
        fields = proc.read_text().rsplit(")", 1)[1].split()
        assert fields[19] != identity or fields[0] == "Z", "The child survived explicit terminal closure"
    assert Path(workspace["path"]).is_dir(), "Closing a terminal removed the shared checkout"
    if action.startswith("restart"):
        restarted = root / f"{action}-owner-terminal.txt"
        command = f"printf 'restarted\\n' > {shlex.quote(str(restarted))}\n"
        rpc("write", {"sessionId": session_id, "dataBase64": base64.b64encode(command.encode()).decode()})
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            if restarted.exists() and restarted.read_text() == "restarted\n":
                break
            time.sleep(0.1)
        else:
            raise AssertionError("The replacement owner terminal did not accept input")
        if action == "restart-completed-replay":
            replacement_marker = root / "replacement-child.pid"
            command = f"sleep 600 & printf '%s\\n' $! > {shlex.quote(str(replacement_marker))}\n"
            rpc("write", {"sessionId": session_id, "dataBase64": base64.b64encode(command.encode()).decode()})
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if replacement_marker.exists() and replacement_marker.read_text().strip():
                    break
                time.sleep(0.1)
            else:
                raise AssertionError("Replacement child did not start")
            replacement_proc = Path(f"/proc/{int(replacement_marker.read_text())}/stat")
            replacement_identity = replacement_proc.read_text().rsplit(")", 1)[1].split()[19]
            rpc("terminal.restart", restart_payload)
            fields = replacement_proc.read_text().rsplit(")", 1)[1].split()
            assert fields[19] == replacement_identity and fields[0] != "Z", "A completed restart replay killed replacement work"
            with sqlite3.connect(f"file:{root}/home-state/runtime.sqlite?mode=ro", uri=True) as database:
                count = database.execute("SELECT count(*) FROM terminalLifecycleOperations WHERE sessionId = ?", (session_id,)).fetchone()[0]
            assert count == 1, "A completed restart replay created a second owner action"
        rpc("terminate", {"sessionId": session_id})
    print(f"Home {action} verified the SSH owner's active child closure", flush=True)
    return {f"home_explicit_terminal_{action}": True}


def _drop_restart_response(root, payload):
    control = json.loads((root / "home-state/runtime-host.json").read_text())
    with socket.create_connection(("127.0.0.1", control["port"]), timeout=30) as connection:
        reader = connection.makefile("rb")
        try:
            hello = {"id": 1, "type": "hello", "payload": {
                "protocolVersion": control["protocolVersion"], "token": control["token"],
                "clientKind": "cli", "sharedCheckoutWorkspacesV1": True,
            }}
            connection.sendall((json.dumps(hello) + "\n").encode())
            while line := reader.readline():
                response = json.loads(line)
                if response.get("id") == 1:
                    assert response.get("ok") is True
                    break
            else:
                raise AssertionError("Fixture client authentication failed")
            connection.sendall((json.dumps({"id": 2, "type": "terminal.restart", "payload": payload}) + "\n").encode())
        finally:
            reader.close()
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        with sqlite3.connect(f"file:{root}/home-state/runtime.sqlite?mode=ro", uri=True) as database:
            record = database.execute("SELECT closed FROM terminalLifecycleOperations WHERE sessionId = ?", (payload["sessionId"],)).fetchone()
        if record == (1,):
            return
        time.sleep(0.1)
    raise AssertionError("The disconnected request did not persist verified owner completion")
