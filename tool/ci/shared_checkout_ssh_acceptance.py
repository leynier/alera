#!/usr/bin/env python3
"""Verify native owner cleanup over an isolated OpenSSH server on Linux.

Build the CLI first with make cli-build. This requires sshd, ssh and ssh-keygen,
a Linux /proc filesystem, and an existing SSH privilege-separation directory.
The output directory must not exist; all runtime state and keys stay inside it.
"""

import argparse
import base64
import hashlib
import json
import os
import pathlib
import pwd
import shlex
import socket
import subprocess
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", type=pathlib.Path, required=True)
parser.add_argument("--output-dir", type=pathlib.Path, required=True)
parser.add_argument("--home-checkouts", action="store_true")
parser.add_argument("--owner-relocation", action="store_true")
parser.add_argument("--owner-prechecks", action="store_true")
options = parser.parse_args()
if sys.platform != "linux":
    parser.error("This fixture verifies Linux process identities through /proc")
binary = options.binary.resolve(strict=True)
root = options.output_dir.absolute()
root.mkdir(mode=0o700, parents=False, exist_ok=False)
state = root / "owner-state"
folder = root / "shared-folder"
folder.mkdir(exist_ok=True)
(folder / "retained.txt").write_text("shared uncommitted content\n")
user = pwd.getpwuid(os.getuid()).pw_name
children = []
sshd = None
owner_started = False
with binary.open("rb") as executable:
    fingerprint = hashlib.file_digest(executable, "sha256").hexdigest()
result = {
    "transport": "OpenSSH loopback",
    "binarySha256": fingerprint,
    "completed": False,
}
identities = {}
env = dict(os.environ)
for key in ["ALERA_RUNTIME_DIR", "ALERA_WORKSPACE_ID", "ALERA_TERMINAL_HANDLE"]:
    env.pop(key, None)


def local(args, **kwargs):
    return subprocess.run(
        args, check=True, capture_output=True, text=True, timeout=60, env=env, **kwargs
    )


def wait_for(predicate, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise RuntimeError("Fixture condition timed out")


def process_identity(pid):
    try:
        row = pathlib.Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1].split()
        return (row[19], row[0])
    except FileNotFoundError:
        return None


def alive(identity):
    current = process_identity(identity[0])
    return current is not None and current[0] == identity[1] and current[1] != "Z"


try:
    for name in ["client-key", "host-key"]:
        local(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(root / name)])
    (root / "authorized_keys").write_text((root / "client-key.pub").read_text())
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    (root / "known_hosts").write_text(
        f"[127.0.0.1]:{port} " + (root / "host-key.pub").read_text()
    )
    config = root / "sshd_config"
    config.write_text(
        f"""Port {port}\nListenAddress 127.0.0.1\nHostKey {root}/host-key\nPidFile {root}/sshd.pid\nAuthorizedKeysFile {root}/authorized_keys\nStrictModes no\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPubkeyAuthentication yes\nUsePAM no\nAllowUsers {user}\nLogLevel ERROR\n"""
    )
    log = (root / "sshd.log").open("w")
    sshd = subprocess.Popen(
        ["/usr/sbin/sshd", "-D", "-e", "-f", str(config)],
        stdout=log,
        stderr=log,
        env=env,
    )
    (root / "processes.json").write_text(
        json.dumps({"sshd": sshd.pid, "port": port, "root": str(root)})
    )

    def listening():
        if sshd.poll() is not None:
            raise RuntimeError("sshd exited: " + (root / "sshd.log").read_text())
        try:
            with socket.create_connection(("127.0.0.1", port), 0.2):
                return True
        except OSError:
            return False

    wait_for(listening)
    ssh = [
        "ssh",
        "-F",
        "/dev/null",
        "-p",
        str(port),
        "-i",
        str(root / "client-key"),
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        f"UserKnownHostsFile={root}/known_hosts",
        "-o",
        "ConnectTimeout=5",
        f"{user}@127.0.0.1",
    ]

    def command(group, args):
        return shlex.join(
            [str(binary), group, "--runtime-dir", str(state), "--json", *args]
        )

    def cli(group, args, expect=True):
        output = subprocess.run(
            [*ssh, command(group, args)],
            check=False,
            capture_output=True,
            text=True,
            timeout=90,
            env=env,
        )
        if expect and output.returncode:
            raise RuntimeError(
                f"{group} {args[0]} failed: {output.stderr}\n{output.stdout}"
            )
        return json.loads(output.stdout) if expect else output

    cli("runtime", ["start"])
    owner_started = True
    print("SSH owner runtime started", flush=True)
    registered = cli(
        "project",
        [
            "add",
            "--name",
            "SSH fixture",
            "--repo-path",
            str(folder),
            "--kind",
            "folder",
        ],
    )
    project = registered.get("project", registered)
    project_id = project["id"]
    tasks = {}
    for name in ["owned", "neighbor", "protected"]:
        created = cli(
            "workspace",
            ["add", "--project-id", project_id, "--id", name, "--name", name],
        )
        tasks[name] = created.get("workspace", created)
    for name, task in tasks.items():
        metadata = base64.b64encode(
            json.dumps({"project": project, "workspace": task}).encode()
        ).decode()
        args = [
            "owner-terminal",
            "--state-dir",
            str(state),
            "--metadata-base64",
            metadata,
            "--session-id",
            f"{name}-session",
            "--tab-id",
            f"{name}-tab",
        ]
        if name == "owned":
            args += ["--automation-run-id", "fixture-run"]
        output = (root / f"{name}-terminal.log").open("wb")
        client = subprocess.Popen(
            [*ssh[:-1], "-tt", ssh[-1], command("project", args)],
            stdin=subprocess.PIPE,
            stdout=output,
            stderr=output,
            env=env,
        )
        children.append(client)
        shell_file = root / f"{name}-shell.pid"
        child_file = root / f"{name}-child.pid"
        script = f"echo $$ > {shlex.quote(str(shell_file))}; /usr/bin/sleep 600 & echo $! > {shlex.quote(str(child_file))}; wait\n"
        client.stdin.write(script.encode())
        client.stdin.flush()
        wait_for(
            lambda shell_file=shell_file, child_file=child_file: (
                shell_file.exists() and child_file.exists()
            )
        )
        identities[name] = []
        for marker in [shell_file, child_file]:
            pid = int(marker.read_text().strip())
            identity = process_identity(pid)
            assert identity is not None
            identities[name].append((pid, identity[0]))
    print("Three SSH terminals and their child processes verified", flush=True)

    def retire(name):
        task = tasks[name]
        scope = {"runId": "fixture-run", "workspace": task, "tabIds": [f"{name}-tab"]}
        encoded = base64.b64encode(json.dumps(scope).encode()).decode()
        return cli(
            "project",
            [
                "retire-owner-workspace",
                "--state-dir",
                str(state),
                "--workspace-id",
                name,
                "--instance-id",
                task["instanceId"],
                "--close-sessions",
                "--automation-cleanup-base64",
                encoded,
            ],
            False,
        )

    rejected = retire("protected")
    assert rejected.returncode != 0, (rejected.stdout, rejected.stderr)
    assert "outside this automation cleanup scope" in rejected.stderr, (
        rejected.stdout,
        rejected.stderr,
    )
    assert all(alive(identity) for group in identities.values() for identity in group)
    print("Unowned terminal rejected without stopping any fixture process", flush=True)
    removed = retire("owned")
    assert removed.returncode == 0, (removed.stdout, removed.stderr)
    receipt = json.loads(removed.stdout)
    assert (
        receipt["processClosureVerified"] is True
        and receipt["workspace"]["id"] == "owned"
    )
    wait_for(lambda: not any(alive(identity) for identity in identities["owned"]))
    assert all(
        alive(identity)
        for name in ["neighbor", "protected"]
        for identity in identities[name]
    )
    assert (folder / "retained.txt").read_text() == "shared uncommitted content\n"
    listed = cli("workspace", ["list", "--project-id", project_id])
    records = listed if isinstance(listed, list) else listed["items"]
    assert "owned" not in [task["id"] for task in records]
    assert {"neighbor", "protected"}.issubset({task["id"] for task in records})
    retry = retire("owned")
    assert retry.returncode == 0, (retry.stdout, retry.stderr)
    assert (
        json.loads(retry.stdout)["workspace"]["instanceId"]
        == tasks["owned"]["instanceId"]
    )
    if options.owner_relocation:
        from shared_checkout_ssh_relocation_cases import verify_owner_relocation

        result.update(verify_owner_relocation(root, state, cli, env))
    if options.home_checkouts or options.owner_prechecks:
        from shared_checkout_ssh_home_cases import verify_home_checkouts

        result.update(verify_home_checkouts(root, binary, env, port, user, options.owner_prechecks))
    result.update(
        completed=True,
        protected_rejection=True,
        owned_processes_closed=True,
        neighbor_processes_preserved=True,
        shared_file_preserved=True,
        receipt_retry=True,
    )
    print("Scoped SSH retirement and receipt retry passed", flush=True)
finally:
    if state.exists():
        try:
            if owner_started:
                stopped = cli("runtime", ["stop", "--force"], False)
                result["owner_stop_exit"] = stopped.returncode
        except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
            result["owner_stop_error"] = str(error)
        if result.get("owner_stop_exit") != 0:
            try:
                local(
                    [
                        str(binary),
                        "runtime",
                        "--runtime-dir",
                        str(state),
                        "stop",
                        "--force",
                    ]
                )
                result["owner_stop_exit"] = 0
                result["local_cleanup_fallback"] = True
            except (
                OSError,
                subprocess.SubprocessError,
                ValueError,
                RuntimeError,
            ) as error:
                result["owner_stop_error"] = str(error)
    for child in children:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    if sshd is not None:
        sshd.terminate()
        try:
            sshd.wait(5)
        except subprocess.TimeoutExpired:
            sshd.kill()
            sshd.wait()
    result["ssh_server_stopped"] = sshd is None or sshd.poll() is not None
    try:
        wait_for(
            lambda: (
                not any(
                    alive(identity)
                    for group in identities.values()
                    for identity in group
                )
            ),
            10,
        )
        result["fixture_processes_closed"] = True
    except RuntimeError:
        result["fixture_processes_closed"] = False
        result["completed"] = False
    if result.get("owner_stop_exit") != 0 or not result["ssh_server_stopped"]:
        result["completed"] = False
    for name in ["client-key", "host-key"]:
        (root / name).unlink(missing_ok=True)
    (root / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)

if not result["completed"]:
    raise SystemExit("SSH acceptance or fixture cleanup did not complete")
