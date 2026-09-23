"""Isolated Home-to-SSH cloning and owner-repository worktree acceptance."""

import hashlib
import json
import shlex
import socket
import subprocess
import time
import uuid

from shared_checkout_ssh_home_relocation_cases import verify_home_relocation
from shared_checkout_ssh_linked_retirement_cases import verify_linked_retirement
from shared_checkout_ssh_terminal_lifecycle_cases import verify_terminal_close


def verify_clone_checkout(root, cli, env, rpc):
    source = root / "clone-source"
    source.mkdir()

    def git(folder, *args):
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

    git(source, "init", "--template=", "--initial-branch=fixture-main")
    (source / "retained.txt").write_text("clone fixture\n")
    git(source, "add", "retained.txt")
    git(source, "commit", "-m", "fixture: initialize isolated checkout")
    project = cli(
        "project", ["add", "--name", "Clone fixture", "--repo-path", str(source)]
    )["project"]
    destination = root / "cloned-owner-project"
    register_args = [
        "register-checkout",
        "--project-id",
        project["id"],
        "--host-id",
        "fixture-ssh",
        "--path",
        str(destination),
        "--clone-url",
        str(source),
    ]
    checkout = cli("project", register_args)
    assert checkout["path"] == str(destination)
    assert (destination / "retained.txt").read_text() == "clone fixture\n"
    assert git(destination, "branch", "--show-current") == "fixture-main"
    try:
        cli("project", register_args)
    except RuntimeError:
        pass
    else:
        raise AssertionError("Cloning into an existing folder must be rejected")
    assert (destination / "retained.txt").read_text() == "clone fixture\n"

    # The owner diverges deliberately; a new remote worktree must use this commit.
    (destination / "owner-only.txt").write_text("owner repository commit\n")
    git(destination, "add", "owner-only.txt")
    git(destination, "commit", "-m", "fixture: advance isolated owner checkout")
    owner_head = git(destination, "rev-parse", "HEAD")
    assert owner_head != git(source, "rev-parse", "HEAD")
    managed = root / "owner-managed-worktrees"
    managed.mkdir()
    linked_path = managed / "owner-linked-task"
    created = cli(
        "workspace",
        [
            "add",
            "--project-id",
            project["id"],
            "--host-id",
            "fixture-ssh",
            "--id",
            "owner-linked",
            "--name",
            "Owner linked task",
            "--worktree",
            "--branch",
            "fixture-linked",
            "--source-branch",
            "fixture-main",
            "--path",
            str(linked_path),
        ],
    )
    workspace = created.get("workspace", created)
    assert workspace["path"] == str(linked_path)
    assert git(linked_path, "rev-parse", "HEAD") == owner_head
    assert (linked_path / "owner-only.txt").read_text() == "owner repository commit\n"
    assert git(destination, "branch", "--show-current") == "fixture-main"
    assert not (source / "owner-only.txt").exists()
    git(source, "branch", "local-only-catalog")
    git(destination, "branch", "remote-only-catalog")
    local_catalog = rpc("project.branches.list", {"projectId": project["id"], "hostId": "local"})
    remote_catalog = rpc("project.branches.list", {"projectId": project["id"], "hostId": "fixture-ssh"})
    for catalog, host, path in [
        (local_catalog, "local", source),
        (remote_catalog, "fixture-ssh", destination),
    ]:
        assert catalog["projectId"] == project["id"]
        assert catalog["hostId"] == host
        assert catalog["path"] == str(path.resolve())
    assert "local-only-catalog" in local_catalog["localBranches"]
    assert "local-only-catalog" not in remote_catalog["branches"]
    assert "remote-only-catalog" in remote_catalog["localBranches"]
    assert "remote-only-catalog" not in local_catalog["branches"]
    print("Branch catalogs use their selected owner without mixing repositories", flush=True)
    print(
        "Home cloned an SSH checkout and created a worktree from the owner's commit",
        flush=True,
    )
    marker = root / "linked-terminal-used.txt"
    cli(
        "tab",
        [
            "create",
            "--workspace-id",
            workspace["id"],
            "--title",
            "Fixture terminal",
            "--spawn",
            "--command",
            f"printf 'owned\\n' > {shlex.quote(str(marker))}; exit",
        ],
    )
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if marker.exists() and rpc("status.get", {})["activeSessions"] == 0:
            break
        time.sleep(0.1)
    else:
        raise AssertionError("The linked owner terminal did not run and exit")
    assert marker.read_text() == "owned\n"
    profile = hashlib.sha256(project["id"].encode()).hexdigest()
    control = json.loads(
        (
            root / "fixture-sidecar" / "owners" / profile / "runtime-host.json"
        ).read_text()
    )
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
                ("runtimeSettings.update", {"workspaceDirectory": str(managed)}),
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
                    break
            else:
                raise AssertionError(
                    "The fixture owner disconnected during configuration"
                )
    returned = cli(
        "workspace",
        [
            "hand-on",
            "--id",
            workspace["id"],
            "--relocation-id",
            str(uuid.uuid4()),
            "--confirm-shared-impact",
        ],
    )["workspace"]
    assert (
        returned["id"] == workspace["id"]
        and returned["instanceId"] == workspace["instanceId"]
    )
    assert returned["path"] == str(destination) and not linked_path.exists()
    print("Linked SSH terminal use preserved the owner needed for Hand On", flush=True)
    return {
        "home_linked_terminal_hand_on": True,
        **verify_terminal_close(root, cli, returned, rpc),
        **verify_linked_retirement(
            root, cli, project, destination, managed, control, git
        ),
        **verify_home_relocation(root, cli, project, source, destination, git, rpc),
        "home_ssh_clone": True,
        "home_clone_existing_rejected": True,
        "home_worktree_uses_owner_repository": True,
    }
