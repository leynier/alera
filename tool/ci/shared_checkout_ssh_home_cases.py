"""Home-runtime cases for the isolated Linux SSH checkout acceptance fixture."""

import datetime
import json
import os
import shlex
import socket
import subprocess

from shared_checkout_ssh_clone_cases import verify_clone_checkout
from shared_checkout_ssh_initial_failure_cases import verify_initial_failure


def verify_home_checkouts(root, binary, env, port, user, prechecks=False):
    state = root / "home-state"
    install = root / "fixture-sidecar"
    (install / "current").mkdir(parents=True)
    (install / "current/alera").symlink_to(binary)
    wrapper_dir = root / "home-bin"
    wrapper_dir.mkdir()
    config = root / "home-ssh-config"
    config.write_text(
        f'Host *\n  IdentityFile "{root}/client-key"\n  IdentitiesOnly yes\n'
        f'  UserKnownHostsFile "{root}/known_hosts"\n  GlobalKnownHostsFile /dev/null\n'
    )
    wrapper = wrapper_dir / "ssh"
    wrapper.write_text(
        '#!/bin/sh\n'
        f'flag={shlex.quote(str(root / "fail-next-owner-terminal"))}\n'
        'case "$*" in *"project owner-terminal "*)\n'
        '  if [ -f "$flag" ]; then\n    rm "$flag"\n'
        f'    exec /usr/bin/ssh -F {shlex.quote(str(config))} -oProxyCommand=false "$@"\n'
        '  fi;;\nesac\n'
        'case "$*" in *"project control-owner-precheck "*"--action start"*)\n'
        f'  echo start >> {shlex.quote(str(root / "owner-precheck-starts.log"))}\n'
        f'  if [ -f {shlex.quote(str(root / "lose-next-owner-precheck-response"))} ]; then\n'
        f'    rm {shlex.quote(str(root / "lose-next-owner-precheck-response"))}\n'
        f'    /usr/bin/ssh -F {shlex.quote(str(config))} "$@" > /dev/null\n'
        '    exit 255\n  fi;;\nesac\n'
        f'exec /usr/bin/ssh -F {shlex.quote(str(config))} "$@"\n'
    )
    wrapper.chmod(0o700)
    home_env = dict(env, PATH=f"{wrapper_dir}{os.pathsep}{env['PATH']}")

    def cli(group, args):
        completed = subprocess.run(
            [str(binary), group, "--runtime-dir", str(state), "--json", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=90,
            env=home_env,
        )
        if completed.returncode:
            raise RuntimeError(
                f"{group} {args[0]}: {completed.stderr} {completed.stdout}"
            )
        return json.loads(completed.stdout)

    connection = None
    reader = None
    try:
        cli("runtime", ["start"])
        sequence = 0

        def rpc(verb, payload):
            nonlocal sequence
            sequence += 1
            connection.sendall(
                (
                    json.dumps({"id": sequence, "type": verb, "payload": payload})
                    + "\n"
                ).encode()
            )
            while line := reader.readline():
                response = json.loads(line)
                if response.get("id") != sequence:
                    continue
                if response.get("ok") is not True:
                    raise RuntimeError(f"{verb}: {response.get('error')}")
                return response.get("payload")
            raise RuntimeError(f"Home runtime disconnected during {verb}")

        def connect_home():
            nonlocal connection, reader
            control = json.loads((state / "runtime-host.json").read_text())
            connection = socket.create_connection(("127.0.0.1", control["port"]), timeout=90)
            reader = connection.makefile("rb")
            rpc("hello", {"protocolVersion": control["protocolVersion"], "token": control["token"],
                          "clientKind": "cli", "sharedCheckoutWorkspacesV1": True})

        def restart_home():
            nonlocal connection, reader
            from shared_checkout_ssh_precheck_cases import identity, wait_for

            previous_pid = json.loads((state / "runtime-host.json").read_text())["pid"]
            previous_identity = identity(previous_pid)
            assert previous_identity is not None
            cli("runtime", ["stop", "--force"])
            reader.close()
            connection.close()
            reader = connection = None
            wait_for(
                lambda: (current := identity(previous_pid)) is None or current[0] != previous_identity[0],
                "previous Home runtime exit",
                20,
            )
            cli("runtime", ["start"])
            connect_home()

        connect_home()
        now = datetime.datetime.now(datetime.UTC).isoformat()
        rpc(
            "sshTarget.upsert",
            {
                "id": "fixture-ssh",
                "alias": "Isolated SSH",
                "host": "127.0.0.1",
                "port": port,
                "username": user,
                "authKind": "key",
                "createdAt": now,
                "updatedAt": now,
                "installDir": str(install),
                "bootstrapStatus": "installed",
                "runtimePlatform": "linux",
            },
        )
        local_folder = root / "home-project"
        remote_folder = root / "remote-project"
        local_folder.mkdir()
        remote_folder.mkdir()
        (remote_folder / "retained.txt").write_text("remote shared content\n")
        project = cli(
            "project",
            [
                "add",
                "--name",
                "Home project",
                "--repo-path",
                str(local_folder),
                "--kind",
                "folder",
            ],
        )
        project = project.get("project", project)
        project_id = project["id"]
        checkout = cli(
            "project",
            [
                "register-checkout",
                "--project-id",
                project_id,
                "--host-id",
                "fixture-ssh",
                "--path",
                str(remote_folder),
            ],
        )
        assert checkout["hostId"] == "fixture-ssh" and checkout["path"] == str(
            remote_folder
        )
        (remote_folder / "remote-quick-open.txt").write_text("remote only")
        (remote_folder / ".gitignore").write_text("quick-open-ignored.txt\n")
        (remote_folder / "quick-open-ignored.txt").write_text("ignored")
        (remote_folder / "quick-open-link.txt").symlink_to("remote-quick-open.txt")
        search_session = rpc("checkout.quickOpen.start", {"projectId": project_id, "hostId": "fixture-ssh"})
        matches = rpc("mobile.workspaceQuickOpen.search", {"sessionId": search_session["sessionId"], "query": "quick-open", "limit": 100})["items"]
        assert any(item["relativePath"] == "remote-quick-open.txt" for item in matches)
        assert not any(item["relativePath"] in {"quick-open-ignored.txt", "quick-open-link.txt"} for item in matches)
        rpc("mobile.workspaceQuickOpen.stop", {"sessionId": search_session["sessionId"]})
        print("SSH Quick Open indexed owner files and excluded ignored files and symlinks", flush=True)
        tasks = []
        for name in ["remote-one", "remote-two"]:
            created = cli(
                "workspace",
                [
                    "add",
                    "--project-id",
                    project_id,
                    "--host-id",
                    "fixture-ssh",
                    "--id",
                    name,
                    "--name",
                    name,
                ],
            )
            task = created.get("workspace", created)
            assert task["hostId"] == "fixture-ssh" and task["path"] == str(
                remote_folder
            )
            assert task.get("parentWorkspaceId") is None
            tasks.append(task)
        assert tasks[0]["instanceId"] != tasks[1]["instanceId"]
        checkouts = rpc("checkout.list", {"projectId": project_id})
        assert {entry["hostId"] for entry in checkouts} == {"local", "fixture-ssh"}
        assert next(entry for entry in checkouts if entry["hostId"] == "fixture-ssh")["hostName"] == "Isolated SSH"
        print(
            "Home registered the SSH folder and created two independent shared tasks",
            flush=True,
        )
        cli(
            "workspace",
            ["remove", "--id", "remote-one", "--close-sessions", "--keep-branch"],
        )
        remaining = cli("workspace", ["list", "--project-id", project_id])["items"]
        assert "remote-one" not in {task["id"] for task in remaining}
        assert "remote-two" in {task["id"] for task in remaining}
        assert (remote_folder / "retained.txt").read_text() == "remote shared content\n"
        print(
            "Home retired a never-opened SSH task without removing shared files",
            flush=True,
        )
        clone_result = verify_clone_checkout(root, cli, home_env, rpc)
        recovery_result = verify_initial_failure(root, cli, rpc)
        precheck_result = {}
        if prechecks:
            from shared_checkout_ssh_precheck_cases import verify_prechecks
            precheck_result = verify_prechecks(root, cli, rpc, restart_home)
        return {
            **precheck_result,
            **clone_result,
            **recovery_result,
            "home_ssh_registration": True,
            "home_shared_creation": True,
            "home_never_opened_retirement": True,
        }
    finally:
        if reader is not None:
            reader.close()
        if connection is not None:
            connection.close()
        profiles = [state]
        if (install / "owners").exists():
            profiles.extend((install / "owners").iterdir())
        for profile in profiles:
            stopped = subprocess.run(
                [
                    str(binary),
                    "runtime",
                    "--runtime-dir",
                    str(profile),
                    "stop",
                    "--force",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
                env=home_env,
            )
            if stopped.returncode:
                raise RuntimeError(
                    f"Failed to stop fixture runtime {profile}: {stopped.stderr}"
                )
