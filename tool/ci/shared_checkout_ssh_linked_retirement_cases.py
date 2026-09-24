"""Owner-verified removal of an active linked task through loopback SSH."""

import json
import shlex
import socket
import time
from pathlib import Path


def verify_linked_retirement(root, cli, project, owner, managed, control, git):
    path = managed / "retired-linked"
    created = cli(
        "workspace",
        [
            "add",
            "--project-id",
            project["id"],
            "--host-id",
            "fixture-ssh",
            "--id",
            "retired-linked",
            "--name",
            "Retired linked",
            "--worktree",
            "--branch",
            "retired-linked",
            "--source-branch",
            "fixture-linked",
            "--path",
            str(path),
        ],
    )
    workspace = created.get("workspace", created)
    marker = root / "retired-linked-child.pid"
    cli(
        "tab",
        [
            "create",
            "--workspace-id",
            workspace["id"],
            "--title",
            "Owned child",
            "--spawn",
            "--command",
            f"sleep 600 & child=$!; printf '%s\\n' \"$child\" > {shlex.quote(str(marker))}; wait",
        ],
    )
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if marker.exists() and marker.read_text().strip():
            break
        time.sleep(0.1)
    else:
        raise AssertionError("The linked owner did not start its fixture child")
    child = int(marker.read_text())
    proc = Path(f"/proc/{child}/stat")
    assert proc.exists()
    identity = proc.read_text().rsplit(")", 1)[1].split()[19]
    cli(
        "workspace",
        ["remove", "--id", workspace["id"], "--close-sessions", "--keep-branch"],
    )
    if proc.exists():
        fields = proc.read_text().rsplit(")", 1)[1].split()
        assert fields[19] != identity or fields[0] == "Z", (
            "The owned child survived removal"
        )
    assert not path.exists()
    assert git(owner, "rev-parse", "--verify", "refs/heads/retired-linked")
    for _ in range(2):
        receipt = _owner_receipt(control, workspace)
        assert receipt["id"] == workspace["id"]
        assert receipt["instanceId"] == workspace["instanceId"]
        assert receipt["kind"] == "linked" and receipt["path"] == str(path)
    print(
        "Linked SSH retirement verified child closure and a durable owner receipt",
        flush=True,
    )
    return {"home_active_linked_retirement": True, "home_linked_owner_receipt": True}


def _owner_receipt(control, workspace):
    with (
        socket.create_connection(
            ("127.0.0.1", control["port"]), timeout=30
        ) as connection,
        connection.makefile("rb") as reader,
    ):
        for sequence, (verb, payload) in enumerate(
            [
                (
                    "hello",
                    {
                        "protocolVersion": control["protocolVersion"],
                        "token": control["token"],
                        "clientKind": "cli",
                        "sharedCheckoutWorkspacesV1": True,
                    },
                ),
                (
                    "workspace.retirementReceipt",
                    {"id": workspace["id"], "instanceId": workspace["instanceId"]},
                ),
            ],
            start=1,
        ):
            connection.sendall(
                (
                    json.dumps({"id": sequence, "type": verb, "payload": payload})
                    + "\n"
                ).encode()
            )
            while line := reader.readline():
                response = json.loads(line)
                if response.get("id") == sequence:
                    assert response.get("ok") is True, response.get("error")
                    if sequence == 2:
                        return response["payload"]
                    break
            else:
                raise AssertionError(
                    "The fixture owner disconnected before returning its receipt"
                )
    raise AssertionError("Missing owner receipt")
