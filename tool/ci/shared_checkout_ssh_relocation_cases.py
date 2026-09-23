"""Owner-side relocation over real SSH, independent of Home routing."""

import base64
import json
import socket
import subprocess
import uuid


def verify_owner_relocation(root, state, cli, env):
    managed = root / "relocation-managed"
    managed.mkdir()
    control = json.loads((state / "runtime-host.json").read_text())
    with (
        socket.create_connection(
            ("127.0.0.1", control["port"]), timeout=30
        ) as connection,
        connection.makefile("rb") as reader,
    ):
        for sequence, verb, payload in [
            (
                1,
                "hello",
                {
                    "protocolVersion": control["protocolVersion"],
                    "token": control["token"],
                    "sharedCheckoutWorkspacesV1": True,
                },
            ),
            (2, "runtimeSettings.update", {"workspaceDirectory": str(managed)}),
        ]:
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
                    break
            else:
                raise RuntimeError("Owner disconnected during fixture configuration")
    folder = root / "relocation-project"
    folder.mkdir()

    def git(*args):
        return subprocess.run(
            [
                "git",
                "-c",
                "core.hooksPath=/dev/null",
                "-c",
                "commit.gpgSign=false",
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "-C",
                str(folder),
                *args,
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        ).stdout.strip()

    git("init", "--template=", "--initial-branch=main")
    (folder / "retained.txt").write_text("original\n")
    git("add", "retained.txt")
    git("commit", "-m", "fixture: initialize relocation repository")
    registration = cli(
        "project", ["add", "--name", "Relocation task", "--repo-path", str(folder)]
    )
    task = registration["initialWorkspace"]
    linked = managed / "linked"

    def relocate(request):
        encoded = base64.b64encode(json.dumps(request).encode()).decode()
        return cli(
            "project",
            [
                "relocate-owner-workspace",
                "--state-dir",
                str(state),
                "--request-base64",
                encoded,
            ],
        )

    off_request = {
        "workspace": task,
        "relocationId": str(uuid.uuid4()),
        "intent": {
            "workspaceId": task["id"],
            "toProjectCheckout": False,
            "destinationPath": str(linked),
            "branch": "ssh-topic",
            "replacementBranch": None,
            "moveChanges": False,
            "sharedImpactConfirmed": True,
        },
    }
    (folder / "retained.txt").write_text("left at source\n")
    off = relocate(off_request)
    assert off["relocation"]["phase"] == "completed"
    assert off["workspace"]["id"] == task["id"]
    assert off["workspace"]["instanceId"] == task["instanceId"]
    assert (folder / "retained.txt").read_text() == "left at source\n"
    assert (linked / "retained.txt").read_text() == "original\n"
    assert git("branch", "--show-current") == "main"
    assert relocate(off_request)["relocation"] == off["relocation"]
    (folder / "retained.txt").write_text("original\n")
    (linked / "retained.txt").write_text("returned changes\n")
    on_request = {
        "workspace": off["workspace"],
        "relocationId": str(uuid.uuid4()),
        "intent": {
            "workspaceId": task["id"],
            "toProjectCheckout": True,
            "destinationPath": None,
            "branch": None,
            "replacementBranch": None,
            "moveChanges": True,
            "sharedImpactConfirmed": True,
        },
    }
    on = relocate(on_request)
    assert on["relocation"]["phase"] == "completed"
    assert on["workspace"]["id"] == task["id"]
    assert on["workspace"]["instanceId"] == task["instanceId"]
    assert on["workspace"]["path"] == task["path"]
    assert not linked.exists()
    assert (folder / "retained.txt").read_text() == "returned changes\n"
    assert git("branch", "--show-current") == "ssh-topic"
    assert relocate(on_request)["relocation"] == on["relocation"]
    print(
        "SSH owner relocated the same task in both directions and replayed both receipts",
        flush=True,
    )
    return {"ssh_owner_relocation_roundtrip": True, "ssh_owner_relocation_retry": True}
