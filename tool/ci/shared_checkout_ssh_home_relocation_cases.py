"""Home-dispatched relocation through the real SSH owner runtime."""

import uuid
from pathlib import Path


def verify_home_relocation(root, cli, project, local, owner, git, rpc):
    config = {"worktree": {"setup": ["printf 'once\\n' >> setup-marker.txt"]}}
    rpc("projectConfig.upsert", {"projectId": project["id"], "config": config})
    tasks = []
    for name in ("relocated-task", "relocation-neighbor"):
        created = cli(
            "workspace",
            [
                "add",
                "--project-id",
                project["id"],
                "--host-id",
                "fixture-ssh",
                "--id",
                name,
                "--name",
                name,
            ],
        )
        tasks.append(created.get("workspace", created))
    task, neighbor = tasks
    assert not (owner / "setup-marker.txt").exists()
    assert not (local / "setup-marker.txt").exists()
    unavailable = cli("workspace", ["recovery", "--id", task["id"]])
    assert unavailable["kind"] == "remoteWorkspaceRelocationRecovery"
    assert unavailable["homeIntents"] == []
    assert unavailable["owner"] is None and unavailable["ownerError"]
    original = (owner / "retained.txt").read_text()
    original_branch = git(owner, "branch", "--show-current")
    (owner / "retained.txt").write_text("left at shared source\n")
    managed = root / "home-relocation-storage"
    managed.mkdir()
    off_args = [
        "hand-off",
        "--id",
        task["id"],
        "--relocation-id",
        str(uuid.uuid4()),
        "--branch",
        "home-relocation",
        "--workspace-root",
        str(managed),
        "--leave-changes",
        "--confirm-shared-impact",
    ]
    off = cli("workspace", off_args)
    moved = off["workspace"]
    linked = Path(moved["path"])
    assert linked.is_relative_to(managed)
    assert (linked / "setup-marker.txt").read_text() == "once\n"
    assert not (owner / "setup-marker.txt").exists()
    assert not (local / "setup-marker.txt").exists()
    assert moved["id"] == task["id"] and moved["instanceId"] == task["instanceId"]
    assert moved["hostId"] == "fixture-ssh" and moved["kind"] == "linked"
    assert (owner / "retained.txt").read_text() == "left at shared source\n"
    assert (linked / "retained.txt").read_text() == original
    assert git(owner, "branch", "--show-current") == original_branch
    assert cli("workspace", off_args)["workspace"]["path"] == str(linked)
    recovery = cli("workspace", ["recovery", "--id", task["id"]])
    assert recovery["homeIntents"][0]["homeCommitted"] is True
    assert recovery["homeIntents"][0]["intent"]["id"] == off["relocationId"]
    assert recovery["owner"]["items"][0]["relocation"]["id"] == off["relocationId"]
    assert recovery["ownerError"] is None
    runtime_recovery = rpc(
        "workspace.sshRelocationRecovery", {"id": task["id"], "limit": 20}
    )
    assert runtime_recovery["kind"] == recovery["kind"]
    assert runtime_recovery["homeIntents"] == recovery["homeIntents"]
    assert runtime_recovery["owner"]["items"] == recovery["owner"]["items"]
    setup = recovery["owner"]["items"][0]["setup"]
    setup_args = ["setup", "--id", task["id"], "--relocation-id", off["relocationId"]]
    assert cli("workspace", setup_args) == setup["report"]
    assert (
        cli("workspace", [*setup_args, "--recover", "--attempt-id", setup["attemptId"]])
        == setup["report"]
    )
    try:
        cli("workspace", [*setup_args, "--cancel", "--attempt-id", str(uuid.uuid4())])
    except RuntimeError:
        pass
    else:
        raise AssertionError("A different owner setup attempt must be rejected")
    assert (linked / "setup-marker.txt").read_text() == "once\n"
    assert recovery["homeIntents"][0]["intent"]["setupConfig"]["worktree"] == {
        "copy": [],
        "setup": config["worktree"]["setup"],
    }
    (owner / "retained.txt").write_text(original)
    (linked / "retained.txt").write_text("returned through Home\n")
    on_args = [
        "hand-on",
        "--id",
        task["id"],
        "--relocation-id",
        str(uuid.uuid4()),
        "--confirm-shared-impact",
    ]
    returned = cli("workspace", on_args)["workspace"]
    assert returned["id"] == task["id"] and returned["instanceId"] == task["instanceId"]
    assert returned["hostId"] == "fixture-ssh" and returned["path"] == str(owner)
    assert not linked.exists()
    assert (owner / "retained.txt").read_text() == "returned through Home\n"
    assert git(owner, "branch", "--show-current") == "home-relocation"
    assert (local / "retained.txt").read_text() == original
    assert git(local, "branch", "--show-current") == "fixture-main"
    assert cli("workspace", on_args)["workspace"]["path"] == str(owner)
    recovery = cli("workspace", ["recovery", "--id", task["id"]])
    assert len(recovery["homeIntents"]) == 2
    assert len(recovery["owner"]["items"]) == 2
    assert all(item["homeCommitted"] for item in recovery["homeIntents"])
    remaining = cli("workspace", ["list", "--project-id", project["id"]])["items"]
    assert any(
        entry["id"] == neighbor["id"] and entry["path"] == str(owner)
        for entry in remaining
    )
    print(
        "Home dispatched both SSH relocation directions with stable identity and exact retries",
        flush=True,
    )
    return {
        "home_ssh_relocation_roundtrip": True,
        "home_ssh_relocation_retry": True,
        "home_ssh_recovery_inspection": True,
        "home_ssh_recovery_runtime_api": True,
        "home_ssh_setup_controls": True,
    }
