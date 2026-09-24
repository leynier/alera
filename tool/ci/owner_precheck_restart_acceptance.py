"""Linux-only owner runtime crash recovery with isolated state and native processes."""

import argparse
import base64
import datetime
import hashlib
import json
import os
import pathlib
import shlex
import signal
import sqlite3
import subprocess
import time
import uuid

from shared_checkout_ssh_precheck_cases import alive, identity, wait_for

parser = argparse.ArgumentParser()
parser.add_argument("--binary", type=pathlib.Path, required=True)
parser.add_argument("--output-dir", type=pathlib.Path, required=True)
options = parser.parse_args()
if not pathlib.Path("/proc/sys/kernel/random/boot_id").exists():
    raise SystemExit("This fixture requires Linux process and boot identities")
binary = options.binary.resolve(strict=True)
root = options.output_dir.resolve()
root.mkdir(parents=True, exist_ok=False)
result = {"completed": False, "binarySha256": hashlib.sha256(binary.read_bytes()).hexdigest()}
processes = []
profiles = []
env = dict(os.environ)
for key in ("ALERA_RUNTIME_DIR", "ALERA_WORKSPACE_ID", "ALERA_TERMINAL_HANDLE"):
    env.pop(key, None)


def cli(arguments, check=True):
    completed = subprocess.run([str(binary), *arguments], env=env, capture_output=True, text=True, timeout=40)
    if check and completed.returncode:
        raise RuntimeError(completed.stderr or completed.stdout)
    return completed


def owner(state, envelope, action, check=True):
    encoded = base64.b64encode(json.dumps(envelope).encode()).decode()
    response = cli(["project", "control-owner-precheck", "--state-dir", str(state),
                    "--metadata-base64", encoded, "--action", action], check)
    return json.loads(response.stdout) if response.returncode == 0 else response


def runtime_identity(state):
    control = json.loads((state / "runtime-host.json").read_text())
    pid = control["pid"]
    observed = identity(pid)
    assert observed is not None and observed[1] != "Z"
    command = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes()
    assert str(state).encode() in command and b"runtime-host" in command
    assert pathlib.Path(f"/proc/{pid}/exe").resolve() == binary
    captured = (pid, observed[0])
    processes.append(captured)
    return captured


def kill_captured(captured):
    if alive(captured):
        os.kill(captured[0], signal.SIGKILL)
    wait_for(lambda: not alive(captured), "captured process exit", 15)


try:
    for scenario in ("open", "closed"):
        folder = root / scenario
        folder.mkdir()
        (folder / "alera.toml").write_text("[automation]\ndeclared = true\n")
        marker = folder / "count"
        root_pid = folder / "root.pid"
        child_pid = folder / "child.pid"
        command = f"printf x >> {shlex.quote(str(marker))}; "
        if scenario == "open":
            command += f"echo $$ > {shlex.quote(str(root_pid))}; sleep 240 & echo $! > {shlex.quote(str(child_pid))}; wait"
        else:
            command += "exit 1"
        now = datetime.datetime.now(datetime.UTC).isoformat()
        envelope = {"project": {"id": "fixture-project", "name": "Fixture", "repoPath": str(folder),
            "kind": "folder", "createdAt": now, "updatedAt": now}, "request": {
            "operationId": str(uuid.uuid4()), "originId": "fixture-home", "runId": "fixture-run",
            "projectId": "fixture-project", "path": str(folder),
            "precheck": {"command": command, "timeoutSeconds": 180}}}
        state = folder / "state"
        profiles.append((state, envelope))
        owner(state, envelope, "start")
        old_runtime = runtime_identity(state)
        roots = []
        if scenario == "open":
            wait_for(lambda: root_pid.exists() and child_pid.exists(), "native process identities")
            for file in (root_pid, child_pid):
                pid = int(file.read_text())
                observed = identity(pid)
                assert observed is not None and observed[1] != "Z"
                captured = (pid, observed[0])
                processes.append(captured)
                roots.append(captured)
            wait_for(lambda: owner(state, envelope, "status")["processes"][0]["phase"] == "spawned", "persisted process identity")
        else:
            wait_for(lambda: owner(state, envelope, "status")["job"].get("outcome") is not None, "persisted native closure")
        kill_captured(old_runtime)
        unavailable = owner(state, envelope, "status", check=False)
        if scenario == "open":
            assert isinstance(unavailable, subprocess.CompletedProcess) and unavailable.returncode != 0
            assert "closure remains unverified" in unavailable.stderr
        else:
            assert unavailable["job"]["outcome"]["kind"] == "rejected"
            # Model the interrupted outcome transaction while retaining actual native closure evidence.
            with sqlite3.connect(state / "runtime.sqlite") as database:
                database.execute("UPDATE ownerAutomationPrechecks SET resultJson = NULL WHERE id = ?", (envelope["request"]["operationId"],))
        cli(["runtime", "--runtime-dir", str(state), "--json", "start"])
        new_runtime = runtime_identity(state)
        assert new_runtime != old_runtime
        shown = owner(state, envelope, "status")
        if scenario == "open":
            assert shown["job"].get("outcome") is None
            assert "closure is unverified" in shown["job"]["attention"]
            assert shown["processes"][0]["phase"] == "spawned"
            cancelled = owner(state, envelope, "cancel")
            assert cancelled["job"]["cancelRequested"] and cancelled["job"].get("outcome") is None
            repeated = owner(state, envelope, "start")
            assert repeated["job"]["processId"] == shown["job"]["processId"]
            removal = cli(["project", "--runtime-dir", str(state), "--json", "remove", "--id", "fixture-project"], check=False)
            assert removal.returncode != 0 and "precheck" in (removal.stdout + removal.stderr).lower()
            for captured in roots:
                kill_captured(captured)
            assert owner(state, envelope, "status")["job"].get("outcome") is None
            result["unknown_closure_retained_after_owner_restart"] = True
        else:
            assert shown["job"]["outcome"]["kind"] == "failed"
            assert shown["processes"][0]["phase"] == "closureVerified"
            result["closed_evidence_recovers_without_command_result"] = True
        assert marker.read_text() == "x"
        cli(["runtime", "--runtime-dir", str(state), "--json", "stop"])
        wait_for(lambda: not alive(new_runtime), "restarted runtime stop", 15)
        print(f"Owner restart {scenario}: one execution, conservative recovery verified", flush=True)
    result["completed"] = True
finally:
    for state, envelope in profiles:
        try:
            owner(state, envelope, "cancel", check=False)
            cli(["runtime", "--runtime-dir", str(state), "--json", "stop"], check=False)
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
    for captured in reversed(processes):
        kill_captured(captured)
    result["fixture_processes_closed"] = all(not alive(captured) for captured in processes)
    (root / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
