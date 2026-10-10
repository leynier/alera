#!/usr/bin/env python3
"""End-to-end acceptance for the MCP parity work, against an isolated runtime.

Starts a runtime in a temporary directory, registers throwaway Git projects,
replaces AI Assist with a deterministic custom command and the agent with a
script that only sleeps, then drives `alera mcp serve` over stdio the way an
MCP client does. Nothing touches the user's own runtime or repositories.

Usage: python3 tool/ci/mcp_parity_acceptance.py --alera path/to/alera [--keep]
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

FAKE_AI = r"""#!/bin/sh
prompt=$(cat)
task=$(printf '%s\n' "$prompt" | sed -n '/^User task:/,$p')
case "$prompt" in
  *"Choose the project"*)
    case "$task" in
      *alpha*|*Alpha*)
        echo '{"project":"Alpha","workspaceName":"Fix Alpha Login","branchName":"fix/alpha-login","section":"Alpha Work"}' ;;
      *)
        echo '{"project":"Unknown","workspaceName":"Unclear Task","branchName":"chore/unclear"}' ;;
    esac ;;
  *"previous generated workspace identity was unavailable"*)
    echo '{"workspaceName":"Retry Name","branchName":"fix/taken","section":"Others"}' ;;
  *"taken branch"*)
    echo '{"workspaceName":"Taken Name","branchName":"fix/taken","section":"Others"}' ;;
  *)
    echo '{"workspaceName":"Beta Docs","branchName":"docs/beta-guide","section":"Others"}' ;;
esac
"""

FAKE_AGENT = """#!/bin/sh
exec sleep 3600
"""


class Failure(Exception):
    pass


def check(condition: bool, message: str) -> None:
    if not condition:
        raise Failure(message)


class Runtime:
    def __init__(self, alera: str, root: Path) -> None:
        self.alera = alera
        self.root = root
        self.runtime_dir = root / "runtime"
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("ALERA_")}
        self.env.pop("HERDR_SOCKET_PATH", None)

    def cli(self, *args: str, stdin: str | None = None, check_exit: bool = True) -> dict:
        command = [self.alera, args[0], f"--runtime-dir={self.runtime_dir}", "--json", *args[1:]]
        result = subprocess.run(command, input=stdin, capture_output=True, text=True, env=self.env, timeout=180)
        if check_exit and result.returncode != 0:
            raise Failure(f"{' '.join(args)} failed: {result.stderr.strip() or result.stdout.strip()}")
        return json.loads(result.stdout) if result.stdout.strip() else {}

    def set_ai_assist(self, script: Path) -> None:
        database = self.runtime_dir / "runtime.sqlite"
        settings = {"enabled": True, "agent": "custom", "customCommand": f"/bin/sh {script}"}
        with sqlite3.connect(database) as connection:
            table = next(
                name
                for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
                if name.lower() == "runtimemetadata"
            )
            columns = {row[1] for row in connection.execute(f"PRAGMA table_info({table})")}
            values = {"key": "settings.aiTextGeneration", "value": json.dumps(settings)}
            if "updatedAt" in columns:
                values["updatedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            names = ", ".join(values)
            marks = ", ".join("?" for _ in values)
            connection.execute(f"INSERT OR REPLACE INTO {table} ({names}) VALUES ({marks})", tuple(values.values()))


class McpClient:
    def __init__(self, runtime: Runtime, access: str) -> None:
        self.process = subprocess.Popen(
            [runtime.alera, "mcp", f"--runtime-dir={runtime.runtime_dir}", "serve", f"--access={access}"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            env=runtime.env,
        )
        self.next_id = 0
        self.notifications: list[dict] = []
        self.initialize = self.request("initialize", {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "parity-acceptance", "title": "Parity Acceptance", "version": "1"},
        })

    def request(self, method: str, params: dict) -> dict:
        self.next_id += 1
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        assert self.process.stdin and self.process.stdout
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise Failure(f"mcp serve closed while answering {method}")
            response = json.loads(line)
            if "id" not in response:
                self.notifications.append(response)
                continue
            if response.get("id") == self.next_id:
                if "error" in response:
                    raise Failure(f"{method}: {response['error']}")
                return response["result"]

    def tool(self, name: str, arguments: dict) -> dict:
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        structured = result.get("structuredContent")
        if result.get("isError"):
            raise Failure(f"{name} failed: {result['content'][0]['text']}")
        check(isinstance(structured, dict), f"{name} returned no structuredContent")
        return structured

    def tool_names(self) -> set[str]:
        return {tool["name"] for tool in self.request("tools/list", {})["tools"]}

    def close(self) -> None:
        self.process.terminate()
        self.process.wait(timeout=10)


def git_repo(path: Path) -> None:
    path.mkdir(parents=True)
    for args in (["init", "-q", "-b", "main"], ["config", "user.email", "t@example.com"], ["config", "user.name", "T"]):
        subprocess.run(["git", *args], cwd=path, check=True)
    (path / "README.md").write_text("fixture\n")
    subprocess.run(["git", "add", "."], cwd=path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=path, check=True)


def wait_for(client: McpClient, operation_id: str) -> dict:
    deadline = time.time() + 180
    while True:
        operation = client.tool("wait_for_workspace_start", {"operationId": operation_id, "timeoutSeconds": 20})
        if operation["status"] != "running" or time.time() > deadline:
            return operation


def prompt_workspace_scenarios(runtime: Runtime, client: McpClient, alpha: dict, beta: dict) -> list[str]:
    passed = []
    tools = client.tool_names()
    for name in ("start_workspace_from_prompt", "get_workspace_start", "wait_for_workspace_start",
                 "list_workspace_starts", "cancel_workspace_start", "retry_workspace_start_launch"):
        check(name in tools, f"{name} is not listed")
    passed.append("prompt workspace tools are listed")

    inferred = client.tool("start_workspace_from_prompt", {"prompt": "Fix the alpha login screen", "clientRequestId": "accept-0001"})
    inferred = wait_for(client, inferred["id"])
    check(inferred["status"] == "completed", f"inferred start ended {inferred['status']}: {inferred.get('error')}")
    check(inferred["projectId"] == alpha["id"], "the project was not inferred from the prompt")
    check(inferred["workspace"]["branch"] == "fix/alpha-login", "unexpected branch")
    check(inferred["workspace"]["kind"] != "main", "auto mode did not use a worktree")
    check(inferred.get("sectionId") == alpha["sectionId"], "the AI-picked section was not assigned")
    check(inferred.get("agent", {}).get("tabId"), "the agent did not launch")
    check("prompt" not in inferred, "the prompt leaked into the public record")
    passed.append("project, name, branch, and section are inferred and the agent launches")

    again = client.tool("start_workspace_from_prompt", {"prompt": "Fix the alpha login screen", "clientRequestId": "accept-0001"})
    check(again["id"] == inferred["id"], "a repeated clientRequestId started a second operation")
    passed.append("a repeated clientRequestId returns the first operation")

    unclear = client.tool("start_workspace_from_prompt", {"prompt": "Tidy things up somewhere"})
    unclear = wait_for(client, unclear["id"])
    check(unclear["status"] == "needsInput", f"unclear prompt ended {unclear['status']}")
    names = {candidate["name"] for candidate in unclear.get("candidates", [])}
    check({"Alpha", "Beta"} <= names, "candidates are missing")
    passed.append("an unclear project returns candidates instead of guessing")

    others = client.tool("start_workspace_from_prompt", {"prompt": "Write the beta guide", "projectId": beta["id"]})
    others = wait_for(client, others["id"])
    check(others["status"] == "completed", f"explicit project ended {others['status']}: {others.get('error')}")
    check(others.get("sectionId") is None, "an Others answer assigned a section")
    passed.append("an Others section answer leaves the workspace without a section")

    checkout = client.tool("start_workspace_from_prompt", {
        "prompt": "Write the beta guide", "projectId": beta["id"], "mode": "projectCheckout", "section": "none"})
    checkout = wait_for(client, checkout["id"])
    check(checkout["status"] == "completed", f"project checkout start ended {checkout['status']}: {checkout.get('error')}")
    check(checkout["workspace"]["path"] == beta["path"], "projectCheckout did not use the project folder")
    passed.append("mode projectCheckout uses the project folder")

    subprocess.run(["git", "branch", "fix/taken"], cwd=alpha["path"], check=True)
    taken = client.tool("start_workspace_from_prompt", {"prompt": "taken branch task", "projectId": alpha["id"]})
    taken = wait_for(client, taken["id"])
    check(taken["status"] == "completed", f"collision start ended {taken['status']}: {taken.get('error')}")
    check(taken["workspace"]["branch"].startswith("fix/taken-"), "a taken branch was not renumbered")
    passed.append("a taken branch is retried and then numbered")
    return passed


def event_scenarios(client: McpClient, beta: dict) -> list[str]:
    passed = []
    check(client.initialize["capabilities"].get("resources", {}).get("subscribe") is True,
          "mcp serve does not offer resource subscriptions")
    uris = {resource["uri"] for resource in client.request("resources/list", {})["resources"]}
    check({"alera://events", "alera://workspace-starts", "alera://inbox"} <= uris, "resources are missing")
    passed.append("resources are listed and subscribable")

    start = client.tool("list_events", {"kinds": ["workspace.start.state"]})
    cursor = start["cursor"]
    client.request("resources/subscribe", {"uri": "alera://workspace-starts"})
    client.notifications.clear()
    operation = client.tool("start_workspace_from_prompt", {"prompt": "Write the beta guide", "projectId": beta["id"], "section": "none"})
    wait_for(client, operation["id"])
    page = client.tool("wait_for_events", {"after": cursor, "kinds": ["workspace.start.state"], "timeoutSeconds": 10})
    events = page["events"]
    check(events and all(event["kind"] == "workspace.start.state" for event in events), "no workspace start events")
    check(any(event["data"].get("status") == "completed" and event["data"].get("operationId") == operation["id"]
              for event in client.tool("list_events", {"after": cursor, "kinds": ["workspace.start.state"]})["events"]),
          "the completed transition was not journaled")
    check(page["cursor"] > cursor, "the cursor did not advance")
    passed.append("wait_for_events returns journaled workspace start transitions by cursor")

    client.request("ping", {})
    updated = [note for note in client.notifications
               if note.get("method") == "notifications/resources/updated"
               and note["params"]["uri"] == "alera://workspace-starts"]
    check(updated, "no resources/updated notification for a subscribed resource")
    contents = client.request("resources/read", {"uri": "alera://workspace-starts"})["contents"][0]
    check(operation["id"] in contents["text"], "reading the resource does not show the operation")
    client.request("resources/unsubscribe", {"uri": "alera://workspace-starts"})
    passed.append("a subscribed resource sends resources/updated and reads back its content")
    return passed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--alera", required=True)
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="alera-mcp-parity-"))
    runtime = Runtime(str(Path(args.alera).resolve()), root)
    client = None
    try:
        ai = root / "fake_ai.sh"
        ai.write_text(FAKE_AI)
        agent = root / "fake_agent.sh"
        agent.write_text(FAKE_AGENT)
        agent.chmod(0o755)
        git_repo(root / "alpha")
        git_repo(root / "beta")
        runtime.cli("runtime", "start")
        alpha = runtime.cli("project", "add", f"--repo-path={root / 'alpha'}", "--name=Alpha")
        beta = runtime.cli("project", "add", f"--repo-path={root / 'beta'}", "--name=Beta")
        alpha = {"id": alpha.get("id") or alpha["project"]["id"], "path": str(root / "alpha")}
        beta = {"id": beta.get("id") or beta["project"]["id"], "path": str(root / "beta")}
        main_workspace = runtime.cli("workspace", "add", f"--project-id={alpha['id']}")
        workspace_id = main_workspace.get("workspace", main_workspace).get("id")
        section = runtime.cli("workspace", "section", "create", "--name=Alpha Work", f"--workspace-id={workspace_id}")
        alpha["sectionId"] = section.get("section", section).get("id") or section.get("sectionId")
        runtime.cli("agent-profile", "create", "--name=Fake Agent", "--agent-type=codex",
                    "--launch-mode=command", f"--command={agent}")
        runtime.set_ai_assist(ai)
        client = McpClient(runtime, "full")
        passed = prompt_workspace_scenarios(runtime, client, alpha, beta)
        passed += event_scenarios(client, beta)
        for line in passed:
            print(f"PASS {line}")
        print(f"{len(passed)} scenario(s) passed")
        return 0
    except Failure as failure:
        print(f"FAIL {failure}", file=sys.stderr)
        return 1
    finally:
        if client:
            client.close()
        runtime.cli("runtime", "stop", "--force", check_exit=False)
        if args.keep:
            print(f"kept {root}")
        else:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
