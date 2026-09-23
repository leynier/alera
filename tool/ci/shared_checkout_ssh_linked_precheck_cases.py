"""Create isolated Git targets for the real SSH precheck acceptance cases."""

import subprocess


def prepare_linked_precheck(root, cli, scenario):
    local = root / f"precheck-{scenario}-local"
    principal = root / f"precheck-{scenario}-principal"
    for folder in (local, principal):
        folder.mkdir()
        def git(*arguments):
            return subprocess.run(
                ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false",
                 "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", *arguments],
                cwd=folder, check=True, capture_output=True, text=True,
            ).stdout.strip()
        git("init", "-b", "main")
        (folder / "alera.toml").write_text("[automation]\ndeclared = true\n")
        (folder / "retained.txt").write_text("shared fixture content\n")
        git("add", "alera.toml", "retained.txt")
        git("commit", "-m", "fixture: declare isolated precheck")
    project = cli("project", ["add", "--name", f"Precheck {scenario}", "--repo-path", str(local)])["project"]
    for task in cli("workspace", ["list", "--project-id", project["id"]])["items"]:
        cli("workspace", ["remove", "--id", task["id"], "--close-sessions", "--keep-branch"])
    cli("project", ["register-checkout", "--project-id", project["id"], "--host-id", "fixture-ssh", "--path", str(principal)])
    managed = root / f"precheck-{scenario}-worktrees"
    managed.mkdir()
    path = managed / "task"
    created = cli("workspace", ["add", "--project-id", project["id"], "--host-id", "fixture-ssh",
        "--id", f"precheck-{scenario}", "--name", f"Precheck {scenario}", "--worktree", "--branch",
        f"precheck-{scenario}", "--source-branch", "main", "--path", str(path)])
    task = created.get("workspace", created)
    assert task["path"] == str(path)
    assert (path / "alera.toml").read_text() == "[automation]\ndeclared = true\n"
    return project, path, task, principal


def prepare_legacy_linked_precheck(root, cli, rpc):
    import sqlite3
    import uuid

    local = root / "precheck-legacy-local"
    local.mkdir()
    def git(*arguments):
        return subprocess.run(
            ["git", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false",
             "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", *arguments],
            cwd=local, check=True, capture_output=True, text=True,
        ).stdout.strip()
    git("init", "-b", "main")
    (local / "alera.toml").write_text("[automation]\ndeclared = true\n")
    (local / "retained.txt").write_text("shared fixture content\n")
    git("add", "alera.toml", "retained.txt")
    git("commit", "-m", "fixture: legacy origin")
    origin = root / "precheck-legacy.git"
    git("clone", "--bare", str(local), str(origin))
    path = root / "precheck-legacy-linked"
    git("--git-dir", str(origin), "worktree", "add", "-b", "legacy-task", str(path), "main")
    project = cli("project", ["add", "--name", "Legacy Precheck", "--repo-path", str(local)])["project"]
    initial = cli("workspace", ["list", "--project-id", project["id"]])["items"]
    task = dict(initial[0])
    for item in initial:
        cli("workspace", ["remove", "--id", item["id"], "--close-sessions", "--keep-branch"])
    task.update(id="legacy-linked", instanceId=str(uuid.uuid4()), hostId="fixture-ssh",
                path=str(path), kind="linked", branch="legacy-task", name="Legacy Linked Precheck")
    # Model a migrated task whose origin was never persisted; do not register a principal.
    task = rpc("workspace.upsert", task)
    with sqlite3.connect(f"file:{root}/home-state/runtime.sqlite?mode=ro", uri=True) as database:
        assert database.execute("SELECT COUNT(*) FROM repositoryCheckouts WHERE projectId = ? AND hostId = 'fixture-ssh' AND kind = 'project'", (project["id"],)).fetchone()[0] == 0
        assert database.execute("SELECT c.repositoryPath FROM repositoryCheckouts c JOIN workspaceCheckoutBindings b ON b.checkoutId = c.id WHERE b.workspaceId = ?", (task["id"],)).fetchone()[0] is None
    return project, path, task, origin
