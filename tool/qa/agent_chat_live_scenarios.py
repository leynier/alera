#!/usr/bin/env python3
"""Acceptance scenarios against an explicit QA runtime using real providers."""

import copy
import json
import math
import os
from pathlib import Path
import re
import sys
import time
import uuid

from agent_chat_runtime_probe import PrivateArgumentParser, ProbeError, Redactor, RuntimeProbe, TERMINAL_TURN_STATES

SCENARIOS = ("smoke", "queue-idempotency", "archive-reopen", "cross-project-delegate", "mcp")
OPT_IN_SCENARIOS = ("interrupt", "provider-switch")
TASK_SETTLED = {"completed", "failed", "interrupted", "cancelled", "needs_input"}
TOOL_TYPES = {"mcp_tool_call", "dynamic_tool_call"}


def require(condition, message):
    if not condition:
        raise ProbeError(message)


def transcript(snapshot):
    fields = ("itemId", "turnId", "type", "text", "reasoningText", "output", "clientMessageId")
    return [{key: item[key] for key in fields if key in item} for item in snapshot.get("items", [])]


def assistant_text(snapshot, turn_id):
    return "\n".join(item.get("text") or "" for item in snapshot.get("items", []) if item.get("type") == "assistant_message" and item.get("turnId") == turn_id)


def idle(snapshot):
    session = snapshot.get("session", {})
    return bool(session) and not session.get("activeTurnId") and session.get("status") not in {"starting", "running", "waiting"} and not snapshot.get("queue") and not snapshot.get("pendingRequests")


def native_tool(item, tool_name, server=None):
    if item.get("type") not in TOOL_TYPES or item.get("status") != "completed":
        return False
    normalized = item.get("normalized") or {}
    data = item.get("data") or {}
    results = [data, normalized.get("result")]
    if isinstance(data, dict):
        results.append(data.get("result"))
    if any(isinstance(result, dict) and (result.get("isError") is True or result.get("success") is False or bool(result.get("error"))) for result in results):
        return False
    names = [item.get("title"), normalized.get("toolName")]
    if isinstance(data, dict):
        names.extend(data.get(key) for key in ("toolName", "name", "tool"))
        for key in ("toolCall", "tool_call", "args"):
            nested = data.get(key)
            if isinstance(nested, dict):
                names.extend(nested.get(field) for field in ("toolName", "tool_name", "name"))
                if isinstance(nested.get("args"), dict):
                    names.append(nested["args"].get("toolName"))
    servers = [normalized.get("server")]
    if isinstance(data, dict):
        servers.extend(data.get(key) for key in ("server", "serverName"))
    if server and any(value is not None and value != server for value in servers):
        return False
    return any(isinstance(name, str) and re.search(r"(?:^|[./_:])" + re.escape(tool_name) + r"$", name) for name in names)


class ScenarioRunner:
    """Assertions consume in-memory wire values; only report() may leave the runner."""

    def __init__(self, probe, args, clock=time.monotonic):
        self.probe, self.args, self.clock = probe, args, clock
        self.run_id = args.run_id or uuid.uuid4().hex
        self.mutations, self.results, self.chats = [], [], {}
        self.deadline = self.clock() + args.timeout
        self.current = "preflight"
        self.checks = []
        self.provider, self.second_provider, self.evidence = None, None, {}

    def remaining(self):
        remaining = self.deadline - self.clock()
        require(remaining > 0, "Scenario deadline exceeded")
        return remaining

    def request(self, verb, payload):
        return self.probe.request(verb, payload, timeout=min(self.args.request_timeout, self.remaining()))

    def wait_snapshot(self, chat_id, predicate, message, timeout=None):
        deadline = min(self.deadline, self.clock() + (timeout or self.remaining()))
        while self.clock() < deadline:
            remaining = min(self.remaining(), deadline - self.clock())
            require(remaining > 0, message)
            snapshot = self.probe.snapshot(chat_id, timeout=min(self.args.request_timeout, remaining))
            if predicate(snapshot):
                return snapshot
            require(snapshot.get("session", {}).get("status") != "error", "QA provider session failed; inspect the captured snapshot")
            self.probe.collect(min(0.25, max(0, deadline - self.clock())))
        raise ProbeError(message)

    def mutate(self, verb, payload, label, replay=False):
        payload = copy.deepcopy(payload)
        payload.setdefault("requestId", "qa-" + self.run_id + "-" + self.current + "-" + label)
        self.mutations.append({"verb": verb, "payload": payload, "replay": replay})
        return self.request(verb, payload)

    def check(self, name, condition, message):
        require(condition, message)
        self.checks.append(name)

    def preflight(self):
        providers = self.request("agentChat.providers", {"workspaceId": self.args.workspace_id}).get("providers", [])
        def selected(kind, instance_id, model):
            provider = next((item for item in providers if item.get("provider") == kind and item.get("providerInstanceId") == instance_id), None)
            require(provider is not None and provider.get("available") is True, "Explicit provider instance is not available in the QA workspace")
            if model and provider.get("modelsSource") in {"discovered", "configured"}:
                require(any(item.get("id") == model for item in provider.get("models", [])), "Explicit model is absent from the provider catalog")
            require(self.args.runtime_mode in provider.get("runtimeModes", []), "Explicit runtime mode is unsupported by the provider")
            return provider
        self.provider = selected(self.args.provider, self.args.provider_instance_id, self.args.model)
        if self.args.second_provider:
            require(self.args.second_provider_instance_id != self.args.provider_instance_id, "Provider switch requires a different explicit provider instance")
            self.second_provider = selected(self.args.second_provider, self.args.second_provider_instance_id, self.args.second_model)
            require("default" in self.second_provider.get("interactionModes", []), "Second provider does not support the default interaction mode")
        if self.args.scenario == "interrupt" or (self.args.scenario == "all" and self.second_provider):
            require(self.provider.get("capabilities", {}).get("interrupt") is True, "Primary provider does not advertise interruption support")

    def create(self):
        payload = {"workspaceId": self.args.workspace_id, "provider": self.args.provider, "providerInstanceId": self.args.provider_instance_id, "runtimeMode": self.args.runtime_mode, "title": "QA " + self.current + " " + self.run_id}
        if self.args.model:
            payload["model"] = self.args.model
        result = self.mutate("agentChat.create", payload, "create")
        chat_id = result.get("chatId")
        require(isinstance(chat_id, str) and chat_id, "Create did not return a chat ID")
        self.chats[chat_id] = self.args.workspace_id
        self.check("chat_created_in_fixture", result.get("snapshot", {}).get("workspaceId") == self.args.workspace_id, "Created chat is outside the explicit QA workspace")
        return chat_id

    def marker(self, suffix="result"):
        return "QA_MARKER_" + self.run_id + "_" + self.current.replace("-", "_") + "_" + suffix

    def send(self, chat_id, text, label, delivery="auto"):
        payload = {"chatId": chat_id, "workspaceId": self.chats[chat_id], "clientMessageId": "qa-message-" + self.run_id + "-" + self.current + "-" + label, "text": text, "delivery": delivery}
        result = self.mutate("agentChat.send", payload, label)
        return result, self.mutations[-1]["payload"]

    def completed(self, chat_id, message_id, marker):
        snapshot = self.wait_snapshot(chat_id, lambda value: idle(value) and all(turn.get("status") in TERMINAL_TURN_STATES for turn in value.get("turns", [])), "Chat did not reach a terminal state before the deadline")
        users = [item for item in snapshot.get("items", []) if item.get("type") == "user_message" and item.get("clientMessageId") == message_id]
        self.check("one_user_message_" + message_id.rsplit("-", 1)[-1], len(users) == 1, "Message was duplicated or absent from the persisted transcript")
        turn_id = users[0].get("turnId")
        turn = next((item for item in snapshot.get("turns", []) if item.get("turnId") == turn_id), {})
        self.check("turn_completed_" + message_id.rsplit("-", 1)[-1], bool(turn_id) and turn.get("status") == "completed", "Provider turn settled without completing successfully")
        self.check("assistant_marker_" + message_id.rsplit("-", 1)[-1], marker in assistant_text(snapshot, turn_id), "Unique marker is absent from assistant output for the expected turn")
        return snapshot, turn_id

    def smoke(self, chat_id):
        marker = self.marker()
        result, payload = self.send(chat_id, "Reply with exactly this marker, without using tools or changing files: " + marker, "send")
        self.check("send_started", result.get("delivery") == "started", "Idle chat send did not start a turn")
        return self.completed(chat_id, payload["clientMessageId"], marker)[0]

    def rejected(self, verb, payload, label, code, check):
        before = len(self.probe.report().get("responses", []))
        try:
            self.mutate(verb, payload, label, replay=code == "request_conflict")
        except ProbeError:
            responses = self.probe.report().get("responses", [])
            response = responses[-1].get("response", {}) if len(responses) > before else {}
            self.check(check, response.get("ok") is False and response.get("errorCode") == code, "Expected host rejection was absent or had a different wire error code")
            return
        raise ProbeError("Expected rejected mutation unexpectedly succeeded")

    def conflict(self, verb, payload, label):
        self.rejected(verb, payload, label, "request_conflict", "payload_conflict")

    def queue_idempotency(self, chat_id):
        first_marker, second_marker = self.marker("first"), self.marker("second")
        first, first_payload = self.send(chat_id, "Without tools or file changes, write the numbers 1 through 100 separated by spaces, then finish with " + first_marker, "first")
        self.check("first_started", first.get("delivery") == "started", "First queue test turn did not start")
        queued, payload = self.send(chat_id, "Reply with exactly this marker, without tools or file changes: " + second_marker, "queued", "queue")
        self.check("second_queued", queued.get("delivery") == "queued" and bool(queued.get("queueId")), "Second message did not enter the real queue; first turn finished too soon or queue admission failed")
        replay = self.mutate("agentChat.send", payload, "queued", replay=True)
        self.check("same_request_replays", replay == queued, "Identical send request did not replay its original receipt")
        self.conflict("agentChat.send", {**payload, "text": payload["text"] + " changed"}, "queued")
        self.completed(chat_id, first_payload["clientMessageId"], first_marker)
        snapshot, _ = self.completed(chat_id, payload["clientMessageId"], second_marker)
        self.check("queue_drained", not snapshot.get("queue") and not snapshot.get("pendingRequests"), "Queue did not drain without an open request")
        self.check("two_completed_turns", len(snapshot.get("turns", [])) == 2 and all(turn.get("status") == "completed" for turn in snapshot["turns"]), "Queue replay or conflict created an extra turn")

    def archive_reopen(self, chat_id):
        before = self.smoke(chat_id)
        archived = self.mutate("agentChat.close", {"chatId": chat_id, "workspaceId": self.chats[chat_id]}, "archive")
        self.check("archive_acknowledged", archived.get("archived") is True, "Archive was not acknowledged")
        snapshot = self.probe.snapshot(chat_id, timeout=min(self.args.request_timeout, self.remaining()))
        self.check("archived_transcript_preserved", snapshot.get("archived") is True and transcript(snapshot) == transcript(before) and snapshot.get("turns") == before.get("turns"), "Archive changed the persisted transcript or turn history")
        reopened = self.mutate("agentChat.reopen", {"chatId": chat_id, "workspaceId": self.chats[chat_id]}, "reopen")
        snapshot = reopened.get("snapshot", {})
        self.check("reopened_with_new_tab", reopened.get("chatId") == chat_id and bool(reopened.get("tabId")) and reopened.get("tabId") != before.get("tabId") and snapshot.get("archived") is False, "Reopen did not restore the same chat in a new tab")
        self.check("reopened_transcript_preserved", transcript(snapshot) == transcript(before) and snapshot.get("turns") == before.get("turns"), "Reopen changed the persisted transcript or turn history")

    def cross_project_delegate(self, chat_id):
        primary = self.request("chatOrchestration.read", {"chatId": chat_id})
        project_id = primary.get("chat", {}).get("projectId")
        require(isinstance(project_id, str) and project_id, "Primary QA chat has no observable project ID")
        marker = self.marker()
        payload = {"task": "Reply with exactly this marker, without using tools or changing files: " + marker, "title": "QA Cross-Project " + self.run_id, "mode": "async", "notify": "never", "agent": {"providerInstanceId": self.args.provider_instance_id}, "runtimeMode": self.args.runtime_mode, "target": {"workspace": {"workspaceId": self.args.second_workspace_id}}}
        if self.args.model:
            payload["agent"]["model"] = self.args.model
        delegated = self.mutate("chatOrchestration.delegate", payload, "delegate")
        payload = self.mutations[-1]["payload"]
        task_id = delegated.get("taskId")
        require(isinstance(task_id, str) and task_id, "Delegation did not return a task ID")
        child = delegated.get("chatId") or delegated.get("childChatId")
        if child:
            self.chats[child] = self.args.second_workspace_id
        replay = self.mutate("chatOrchestration.delegate", payload, "delegate", replay=True)
        self.check("delegate_receipt_replays", replay == delegated, "Identical delegation did not replay its original receipt")
        self.conflict("chatOrchestration.delegate", {**payload, "task": payload["task"] + " changed"}, "delegate")
        while True:
            task = self.request("chatOrchestration.task", {"taskId": task_id}).get("task", {})
            child = task.get("childChatId") or child
            if child:
                self.chats[child] = self.args.second_workspace_id
            if task.get("status") in TASK_SETTLED:
                break
            self.probe.collect(min(0.25, self.remaining()))
        self.check("delegate_completed", task.get("status") == "completed", "Delegated task did not complete successfully")
        self.check("different_project_target", task.get("workspaceId") == self.args.second_workspace_id and bool(task.get("projectId")) and task["projectId"] != project_id, "Delegation did not execute in the explicit second workspace of a different project")
        self.check("delegate_result_marker", marker in (task.get("result", {}).get("text") or ""), "Completed task result does not contain its unique marker")
        require(isinstance(child, str) and child, "Completed task has no child chat")
        self.completed(child, "chat-orchestration-task:" + task_id, marker)
        tasks = self.request("chatOrchestration.tasks.list", {"workspaceId": self.args.second_workspace_id, "limit": 200}).get("tasks", [])
        self.check("one_delegated_task", sum(item.get("taskId") == task_id for item in tasks) == 1 and sum(item.get("title") == payload["title"] for item in tasks) == 1, "Delegation replay or conflict created another task")

    def switch_payload(self, chat_id):
        payload = {"chatId": chat_id, "workspaceId": self.chats[chat_id], "provider": self.args.second_provider, "providerInstanceId": self.args.second_provider_instance_id, "runtimeMode": self.args.runtime_mode, "interactionMode": "default"}
        if self.args.second_model:
            payload["model"] = self.args.second_model
        return payload

    def interrupt(self, chat_id):
        self.smoke(chat_id)
        result, _ = self.send(chat_id, "Without tools or file changes, write the numbers 1 through 2000, one per line, then finish with " + self.marker("long_done"), "sustained")
        turn_id = result.get("turnId")
        require(result.get("delivery") == "started" and isinstance(turn_id, str) and turn_id, "Sustained message did not start an identifiable turn")
        def active(snapshot):
            turn = next((turn for turn in snapshot.get("turns", []) if turn.get("turnId") == turn_id), {})
            require(turn.get("status") not in TERMINAL_TURN_STATES, "Turn finished before native interruption could be exercised")
            native = any(item.get("turnId") == turn_id and item.get("type") in {"assistant_message", "reasoning"} and (item.get("text") or item.get("reasoningText")) for item in snapshot.get("items", []))
            return snapshot.get("session", {}).get("activeTurnId") == turn_id and turn.get("status") == "running" and native
        self.evidence["activeTurn"] = self.wait_snapshot(chat_id, active, "Native active turn was not observed before interruption", timeout=30)
        self.checks.append("native_active_turn_observed")
        if self.second_provider:
            self.rejected("agentChat.configure", self.switch_payload(chat_id), "busy-switch", "turnActive", "busy_provider_switch_rejected")
        interrupted = self.mutate("agentChat.interrupt", {"chatId": chat_id, "workspaceId": self.chats[chat_id], "turnId": turn_id}, "interrupt")
        self.check("interrupt_acknowledged", interrupted.get("acknowledged") is True and interrupted.get("interrupted") is True, "Interrupt did not acknowledge the exact active turn")
        terminal = self.wait_snapshot(chat_id, lambda value: any(turn.get("turnId") == turn_id and turn.get("status") in TERMINAL_TURN_STATES for turn in value.get("turns", [])), "Interrupted turn did not settle before the deadline", timeout=60)
        self.evidence["terminalTurn"] = terminal
        turn = next(turn for turn in terminal["turns"] if turn["turnId"] == turn_id)
        self.check("exact_turn_interrupted", turn.get("status") in {"interrupted", "cancelled"}, "Target turn settled without an interrupted or cancelled status")
        settled = self.wait_snapshot(chat_id, lambda value: idle(value) and value.get("session", {}).get("status") == "ready", "Interrupted chat did not become natively ready and idle")
        self.check("interrupted_items_settled", not any(item.get("turnId") == turn_id and (item.get("streaming") or item.get("status") == "inProgress") for item in settled.get("items", [])), "Interrupted turn still has streaming or in-progress items")
        self.evidence["idleAfterInterrupt"] = settled

    def provider_switch(self, chat_id):
        context, seed_marker = "QA_PUBLIC_CONTEXT_" + self.run_id, self.marker("seed")
        _, payload = self.send(chat_id, "Remember the public QA reference phrase " + context + ". Without tools or file changes, reply with that phrase and " + seed_marker, "seed")
        before, seed_turn = self.completed(chat_id, payload["clientMessageId"], context)
        self.check("seed_reply_marker", seed_marker in assistant_text(before, seed_turn), "Seed turn did not confirm the reference phrase")
        self.evidence["beforeSwitch"] = before
        configured = self.mutate("agentChat.configure", self.switch_payload(chat_id), "switch")
        after = configured.get("snapshot")
        require(isinstance(after, dict), "Provider configure did not return the snapshot envelope")
        self.evidence["afterSwitch"] = after
        generation = before.get("session", {}).get("generation")
        self.check("same_chat_and_tab", all(after.get(key) == before.get(key) for key in ("chatId", "workspaceId", "tabId")) and after.get("archived") is False, "Provider switch replaced or archived the chat or tab")
        self.check("provider_generation_changed", isinstance(generation, int) and after.get("session", {}).get("generation") == generation + 1 and after.get("provider") == self.args.second_provider and after.get("providerInstanceId") == self.args.second_provider_instance_id, "Provider switch did not select the requested new generation")
        self.check("switch_history_preserved", after.get("items") == before.get("items") and after.get("turns") == before.get("turns"), "Provider switch changed the persisted prior history")
        ready = self.wait_snapshot(chat_id, lambda value: idle(value) and value.get("session", {}).get("status") == "ready", "Second provider did not reach native idle readiness", timeout=60)
        self.evidence["readyAfterSwitch"] = ready
        self.check("ready_provider_attribution", ready.get("provider") == self.args.second_provider and ready.get("providerInstanceId") == self.args.second_provider_instance_id and ready.get("session", {}).get("generation") == generation + 1, "Ready session belongs to the wrong provider or generation")
        self.check("ready_history_preserved", ready.get("items") == before.get("items") and ready.get("turns") == before.get("turns"), "Second provider startup changed prior history or created a turn")
        marker = self.marker("recall")
        prompt = "Without tools or file changes, repeat the public QA reference phrase from earlier in this conversation, then append " + marker
        self.check("recall_prompt_excludes_context", context not in prompt, "Recall prompt exposes the reference phrase instead of exercising handoff")
        _, payload = self.send(chat_id, prompt, "recall")
        snapshot, turn_id = self.completed(chat_id, payload["clientMessageId"], context)
        self.evidence["recallCompleted"] = snapshot
        turn = next(turn for turn in snapshot["turns"] if turn["turnId"] == turn_id)
        self.check("recall_provider_attribution", turn.get("provider") == self.args.second_provider and turn.get("providerInstanceId") == self.args.second_provider_instance_id and turn.get("generation") == generation + 1, "Recall turn belongs to the wrong provider or generation")
        self.check("recall_reply_marker", marker in assistant_text(snapshot, turn_id), "Expected recall marker is absent from the new provider's own reply")

    def mcp(self, chat_id):
        capabilities = self.request("chatOrchestration.capabilities", {})
        selected = next((item for item in capabilities.get("providers", []) if item.get("providerInstanceId") == self.args.provider_instance_id), {})
        require(selected.get("orchestration", {}).get("supported") is True, "Provider does not advertise injected chat orchestration support")
        marker = self.marker()
        prompt = "Use the injected alera MCP server. Discover its actual available tools through native MCP tools/list (use tools_list if your provider exposes that discovery tool), then actually call alera's chat_capabilities with {}. Do not run shell commands, inspect credentials, change files, delegate, or substitute a written description for a tool call. Only after the capability call succeeds, finish with this exact marker: " + marker
        _, payload = self.send(chat_id, prompt, "mcp-send")
        snapshot, turn_id = self.completed(chat_id, payload["clientMessageId"], marker)
        items = [item for item in snapshot.get("items", []) if item.get("turnId") == turn_id]
        self.check("native_chat_capabilities_call", any(native_tool(item, "chat_capabilities", server="alera") for item in items), "No completed native chat_capabilities tool item from alera was persisted")
        discovery = any(native_tool(item, "tools_list") or native_tool(item, "tools/list") for item in items)
        if self.args.require_tools_list_event:
            self.check("native_tools_list_call", discovery, "Provider did not persist a completed native tools_list discovery item")
        self.checks.append("tools_list_event_observed" if discovery else "tools_list_event_not_observed")

    def cleanup(self, result):
        result["cleanup"] = []
        for chat_id, workspace_id in self.chats.items():
            payload = {"chatId": chat_id, "workspaceId": workspace_id, "requestId": "qa-" + self.run_id + "-cleanup-" + chat_id}
            self.mutations.append({"verb": "agentChat.close", "payload": payload, "cleanup": True})
            try:
                closed = self.probe.request("agentChat.close", payload, timeout=min(10, self.args.request_timeout))
                snapshot = self.probe.snapshot(chat_id, timeout=min(10, self.args.request_timeout))
                settled = idle(snapshot) and all(turn.get("status") in TERMINAL_TURN_STATES for turn in snapshot.get("turns", [])) and not any(item.get("streaming") or item.get("status") == "inProgress" for item in snapshot.get("items", []))
                require(closed.get("archived") is True and snapshot.get("archived") is True and snapshot.get("session", {}).get("status") == "stopped" and settled, "Fixture cleanup did not reach archived, stopped and empty state")
                result["cleanup"].append({"chatId": chat_id, "archived": True, "stopped": True})
            except ProbeError as error:
                result["cleanup"].append({"chatId": chat_id, "error": str(error) + "; use the recorded cleanup request ID"})
                result["ok"] = False

    def run(self):
        self.preflight()
        names = SCENARIOS if self.args.scenario == "all" else (self.args.scenario,)
        if self.args.scenario == "all" and self.second_provider:
            names += OPT_IN_SCENARIOS
        for name in names:
            self.current, self.checks, self.chats, self.evidence = name, [], {}, {}
            self.deadline = self.clock() + self.args.timeout
            result = {"scenario": name, "ok": False, "checks": self.checks, "evidence": self.evidence}
            self.results.append(result)
            try:
                chat_id = self.create()
                getattr(self, name.replace("-", "_"))(chat_id)
                result["ok"] = True
            except ProbeError as error:
                result["error"] = str(error)
            finally:
                result["chatIds"] = list(self.chats)
                self.cleanup(result)
            if not result["ok"]:
                break

    def report(self):
        return self.probe.redactor.clean({"runId": self.run_id, "ok": bool(self.results) and all(item["ok"] for item in self.results), "scenarios": self.results, "mutations": self.mutations, "probe": self.probe.report()})


def arguments(argv=None):
    parser = PrivateArgumentParser(description=__doc__)
    location = parser.add_mutually_exclusive_group(required=True)
    location.add_argument("--control-file", help="Explicit already-running QA host control JSON")
    location.add_argument("--runtime-dir", help="Explicit QA runtime directory; tries host.json, then runtime-host.json")
    parser.add_argument("--workspace-id", required=True, help="Existing isolated QA fixture workspace ID")
    parser.add_argument("--second-workspace-id", help="Existing QA workspace in a different project; required for delegation")
    parser.add_argument("--provider", required=True)
    parser.add_argument("--provider-instance-id", required=True)
    parser.add_argument("--model", help="Exact reported model ID; omission selects the host's provider default")
    parser.add_argument("--second-provider", help="Explicit destination provider for provider-switch or opt-in all")
    parser.add_argument("--second-provider-instance-id", help="Exact destination provider instance ID")
    parser.add_argument("--second-model", help="Exact destination model ID; omission selects its provider default")
    parser.add_argument("--runtime-mode", default="approval-required", choices=("approval-required", "auto-accept-edits", "auto", "full-access"))
    parser.add_argument("--scenario", required=True, choices=SCENARIOS + OPT_IN_SCENARIOS + ("all",))
    parser.add_argument("--timeout", type=float, default=180, help="Total per-scenario deadline in seconds")
    parser.add_argument("--request-timeout", type=float, default=30, help="Individual RPC deadline in seconds")
    parser.add_argument("--run-id", help="Unique public run identifier; recorded request IDs are derived from it")
    parser.add_argument("--require-tools-list-event", action="store_true", help="Require native discovery item where the provider exposes tools_list")
    parser.add_argument("--output", help="Also write the sanitized report with mode 0600")
    args = parser.parse_args(argv)
    if any(not math.isfinite(value) or value <= 0 for value in (args.timeout, args.request_timeout)):
        parser.error("Invalid deadline")
    if args.scenario in {"all", "cross-project-delegate"} and (not args.second_workspace_id or args.second_workspace_id == args.workspace_id):
        parser.error("Delegation requires a distinct second workspace")
    if args.run_id and not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.run_id):
        parser.error("Invalid run ID")
    second = bool(args.second_provider or args.second_provider_instance_id or args.second_model)
    if (second or args.scenario == "provider-switch") and (args.scenario not in {"provider-switch", "all"} or not args.second_provider or not args.second_provider_instance_id):
        parser.error("Provider switch requires both second-provider options and scenario provider-switch or all")
    return args


def connect(args, redactor):
    controls = [Path(args.control_file).expanduser()] if args.control_file else [Path(args.runtime_dir).expanduser() / name for name in ("host.json", "runtime-host.json")]
    last_error = ProbeError("No control file exists in the explicit QA runtime directory")
    for control in controls:
        if args.runtime_dir and not control.is_file():
            continue
        try:
            return RuntimeProbe(control, timeout=args.request_timeout, redactor=redactor)
        except ProbeError as error:
            last_error = error
    raise last_error


def main(argv=None):
    args = arguments(argv)
    probe, runner, redactor = None, None, Redactor()
    report = {"ok": False}
    try:
        probe = connect(args, redactor)
        runner = ScenarioRunner(probe, args)
        runner.run()
    except ProbeError as error:
        report["error"] = str(error)
        if error.report:
            report["probe"] = error.report
    except KeyboardInterrupt:
        report["error"] = "Scenario run interrupted"
    except Exception as error:
        report["error"] = "Scenario runner failed (%s); raw details suppressed" % type(error).__name__
    finally:
        if runner is not None:
            report = {**runner.report(), **report} if report.get("error") else runner.report()
        elif probe is not None:
            report["probe"] = probe.report()
        if probe is not None:
            probe.close()
    rendered = json.dumps(redactor.clean(report), ensure_ascii=False, indent=2) + "\n"
    if args.output:
        try:
            fd = os.open(Path(args.output).expanduser(), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as target:
                os.fchmod(target.fileno(), 0o600)
                target.write(rendered)
        except OSError:
            sys.stderr.write("Could not write sanitized output file.\n")
            return 1
    sys.stdout.write(rendered)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
