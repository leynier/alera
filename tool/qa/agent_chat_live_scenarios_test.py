"""Offline acceptance-runner checks with a deterministic RuntimeProbe fixture."""

import copy
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from agent_chat_live_scenarios import ScenarioRunner, arguments, main
from agent_chat_runtime_probe import ProbeError, Redactor, RuntimeProbe

PRIVATE = "fixture-provider-private-key"


def options(scenario="all", *extra):
    return arguments(["--control-file", "/unused/qa-host.json", "--workspace-id", "qa-one", "--second-workspace-id", "qa-two", "--provider", "codex", "--provider-instance-id", "codex", "--model", "fixture-model", "--scenario", scenario, "--run-id", "fixture", *extra])


SECOND_PROVIDER = ("--second-provider", "grok", "--second-provider-instance-id", "grok", "--second-model", "grok-fixture-model")


class ManualClock:
    def __init__(self):
        self.value = 100.0

    def __call__(self):
        return self.value


class FakeRuntimeProbe(RuntimeProbe):
    def __init__(self):
        self.redactor = Redactor()
        self.redactor.register(PRIVATE)
        self.responses, self.snapshots, self.receipts = [], {}, {}
        self.pending, self.active, self.tasks, self.requests = {}, {}, {}, []
        self.clock, self.snapshot_timeouts, self.contexts = ManualClock(), [], {}
        self.completed_status = "completed"
        self.assistant_marker = True
        self.queue_busy = True
        self.conflict_code = "request_conflict"
        self.second_project = "project-two"
        self.emit_mcp = True
        self.mcp_error = False
        self.emit_discovery = False
        self.wait_error = None
        self.closed = False
        self.second_available, self.handoff, self.switch_ready = True, True, True
        self.configure_fault, self.cleanup_fault, self.mcp_server = None, None, "alera"
        self.interrupt_status, self.busy_switch_code = "interrupted", "turnActive"
        self.sustained_race, self.wrong_recall_provider = False, False

    def close(self):
        self.closed = True

    def collect(self, seconds):
        self.clock.value += seconds

    def report(self):
        return self.redactor.clean({"responses": self.responses, "snapshots": self.snapshots, "eventsDropped": 0, "host": {"token": PRIVATE}, "diagnostic": "provider key " + PRIVATE})

    def snapshot(self, chat_id, timeout=None):
        assert timeout is not None and timeout > 0
        self.snapshot_timeouts.append(timeout)
        snapshot = self.snapshots[chat_id]
        if self.wait_error and not snapshot["archived"]:
            raise ProbeError(self.wait_error)
        if snapshot["session"]["status"] == "starting" and self.switch_ready:
            snapshot["session"]["status"] = "ready"
        active = self.active.get(chat_id)
        if active and ("numbers 1 through 2000" not in active["text"] or self.sustained_race):
            self.finish(chat_id, active)
        if not snapshot["archived"] and not self.active.get(chat_id):
            for payload in self.pending.pop(chat_id, []):
                self.start(chat_id, payload)
                self.finish(chat_id, payload)
            snapshot["queue"] = []
        return copy.deepcopy(self.snapshots[chat_id])

    def start(self, chat_id, payload):
        snapshot = self.snapshots[chat_id]
        turn_id = "turn-" + str(len(snapshot["turns"]) + 1)
        snapshot["turns"].append({"turnId": turn_id, "status": "running", "provider": snapshot["provider"], "providerInstanceId": snapshot["providerInstanceId"], "generation": snapshot["session"]["generation"]})
        message = payload["clientMessageId"]
        snapshot["items"].append({"itemId": message, "type": "user_message", "turnId": turn_id, "clientMessageId": message, "text": payload["text"], "status": "completed"})
        snapshot["session"].update(status="running", activeTurnId=turn_id)
        self.active[chat_id] = payload
        if "numbers 1 through 2000" in payload["text"]:
            snapshot["items"].append({"itemId": "assistant-" + message, "type": "assistant_message", "turnId": turn_id, "text": "1\n2", "status": "inProgress", "streaming": True})
        return turn_id

    def finish(self, chat_id, payload):
        snapshot = self.snapshots[chat_id]
        user = next(item for item in snapshot["items"] if item.get("clientMessageId") == payload["clientMessageId"])
        turn_id, message = user["turnId"], payload["clientMessageId"]
        turn = next(turn for turn in snapshot["turns"] if turn["turnId"] == turn_id)
        turn["status"] = self.completed_status
        marker = payload["text"].rsplit(" ", 1)[-1]
        context = next((word.rstrip(".") for word in payload["text"].split() if word.startswith("QA_PUBLIC_CONTEXT_")), None)
        if context:
            self.contexts[chat_id] = context
        if context or ("reference phrase from earlier" in payload["text"] and self.handoff):
            marker = self.contexts[chat_id] + " " + marker
        snapshot["items"] = [item for item in snapshot["items"] if item["itemId"] != "assistant-" + message]
        snapshot["items"].append({"itemId": "assistant-" + message, "type": "assistant_message", "turnId": turn_id, "text": marker if self.assistant_marker else "No marker", "status": "completed", "streaming": False})
        if "reference phrase from earlier" in payload["text"] and self.wrong_recall_provider:
            turn["provider"] = "codex"
        self.active.pop(chat_id, None)
        snapshot["session"].pop("activeTurnId", None)
        snapshot["session"]["status"] = "ready"
        if "actual available tools" in payload["text"]:
            if self.emit_mcp:
                snapshot["items"].append({"itemId": "mcp-" + message, "type": "mcp_tool_call", "turnId": turn_id, "status": "completed", "title": "mcp__alera__chat_capabilities", "normalized": {"server": self.mcp_server}, "data": {"token": PRIVATE, "result": {"isError": self.mcp_error}}})
            if self.emit_discovery:
                snapshot["items"].append({"itemId": "discovery-" + message, "type": "dynamic_tool_call", "turnId": turn_id, "status": "completed", "normalized": {"toolName": "tools_list"}})

    def request(self, verb, payload, timeout=None, record=True):
        assert timeout is not None and timeout > 0
        payload = copy.deepcopy(payload)
        self.requests.append((verb, payload, timeout))
        request_id = payload.get("requestId")
        key = (verb, request_id)
        digest = json.dumps(payload, sort_keys=True)
        if request_id and key in self.receipts:
            stored, response = self.receipts[key]
            if digest != stored:
                self.responses.append({"verb": verb, "response": {"ok": False, "errorCode": self.conflict_code, "error": PRIVATE}})
                raise ProbeError("Host rejected " + verb + "; inspect the sanitized response")
            response = copy.deepcopy(response)
        else:
            response = self.dispatch(verb, payload)
            if request_id:
                self.receipts[key] = (digest, copy.deepcopy(response))
        self.responses.append({"verb": verb, "response": {"ok": True, "payload": copy.deepcopy(response)}})
        return response

    def dispatch(self, verb, payload):
        if verb == "agentChat.providers":
            return {"providers": [{"provider": kind, "providerInstanceId": kind, "available": kind == "codex" or self.second_available, "modelsSource": "discovered", "models": [{"id": model}], "runtimeModes": ["approval-required"], "interactionModes": ["default"], "capabilities": {"interrupt": True}} for kind, model in (("codex", "fixture-model"), ("grok", "grok-fixture-model"))]}
        if verb == "chatOrchestration.capabilities":
            return {"providers": [{"providerInstanceId": "codex", "orchestration": {"supported": True}}]}
        if verb == "agentChat.create":
            chat_id = "chat-" + str(len(self.snapshots) + 1)
            snapshot = {"chatId": chat_id, "workspaceId": payload["workspaceId"], "tabId": "tab-" + chat_id, "archived": False, "provider": payload.get("provider", "codex"), "providerInstanceId": payload.get("providerInstanceId", "codex"), "session": {"status": "ready", "generation": 1}, "items": [], "turns": [], "queue": [], "pendingRequests": []}
            self.snapshots[chat_id] = snapshot
            return {"chatId": chat_id, "tabId": snapshot["tabId"], "snapshot": copy.deepcopy(snapshot)}
        if verb == "agentChat.send":
            chat_id = payload["chatId"]
            busy = bool(self.active.get(chat_id)) and self.queue_busy
            if busy:
                self.pending.setdefault(chat_id, []).append(payload)
                queue_id = "queue-" + payload["clientMessageId"]
                self.snapshots[chat_id]["queue"].append({"queueId": queue_id, "clientMessageId": payload["clientMessageId"]})
                return {"delivery": "queued", "queueId": queue_id}
            return {"delivery": "started", "turnId": self.start(chat_id, payload)}
        if verb == "agentChat.interrupt":
            snapshot = self.snapshots[payload["chatId"]]
            turn = next(turn for turn in snapshot["turns"] if turn["turnId"] == payload["turnId"])
            turn["status"] = self.interrupt_status
            self.active.pop(payload["chatId"], None)
            snapshot["session"].pop("activeTurnId", None)
            snapshot["session"]["status"] = "ready"
            for item in snapshot["items"]:
                if item.get("turnId") == payload["turnId"]:
                    item.update(status="failed", streaming=False)
            return {"acknowledged": True, "interrupted": True}
        if verb == "agentChat.configure":
            snapshot = self.snapshots[payload["chatId"]]
            if snapshot["session"].get("activeTurnId"):
                self.responses.append({"verb": verb, "response": {"ok": False, "errorCode": self.busy_switch_code}})
                raise ProbeError("Host rejected busy provider switch")
            snapshot.update(provider=payload["provider"], providerInstanceId=payload["providerInstanceId"])
            snapshot["session"].update(status="starting", generation=snapshot["session"]["generation"] + (self.configure_fault != "generation"))
            if self.configure_fault == "tab":
                snapshot["tabId"] = "different-tab"
            if self.configure_fault == "history":
                snapshot["items"][0]["text"] = "Changed prior history"
            return copy.deepcopy(snapshot) if self.configure_fault == "envelope" else {"snapshot": copy.deepcopy(snapshot)}
        if verb == "agentChat.close":
            snapshot = self.snapshots[payload["chatId"]]
            snapshot.update(archived=True, queue=[], pendingRequests=[])
            snapshot["session"].update(status="stopped")
            snapshot["session"].pop("activeTurnId", None)
            self.pending.pop(payload["chatId"], None)
            self.active.pop(payload["chatId"], None)
            for turn in snapshot["turns"]:
                if turn["status"] == "running":
                    turn["status"] = "interrupted"
            for item in snapshot["items"]:
                item["streaming"] = False
                if item.get("status") == "inProgress":
                    item["status"] = "failed"
            if self.cleanup_fault == "status":
                snapshot["session"]["status"] = "ready"
            elif self.cleanup_fault == "active":
                snapshot["session"]["activeTurnId"] = "leftover-turn"
            elif self.cleanup_fault in {"queue", "pendingRequests"}:
                snapshot[self.cleanup_fault] = [{"id": "leftover"}]
            elif self.cleanup_fault == "streaming":
                snapshot["items"][0]["streaming"] = True
            return {"archived": True}
        if verb == "agentChat.reopen":
            snapshot = self.snapshots[payload["chatId"]]
            snapshot["archived"] = False
            snapshot["tabId"] = "reopened-" + snapshot["tabId"]
            return {"chatId": payload["chatId"], "tabId": snapshot["tabId"], "snapshot": copy.deepcopy(snapshot)}
        if verb == "chatOrchestration.read":
            return {"chat": {"projectId": "project-one"}, "messages": []}
        if verb == "chatOrchestration.delegate":
            workspace_id = payload["target"]["workspace"]["workspaceId"]
            child = self.dispatch("agentChat.create", {"workspaceId": workspace_id})["chatId"]
            task_id = "task-" + str(len(self.tasks) + 1)
            message = {"clientMessageId": "chat-orchestration-task:" + task_id, "text": payload["task"]}
            self.pending[child] = [message]
            self.tasks[task_id] = {"taskId": task_id, "childChatId": child, "workspaceId": workspace_id, "projectId": self.second_project, "status": "running", "title": payload["title"], "result": {"text": payload["task"].rsplit(" ", 1)[-1]}}
            return {"taskId": task_id, "chatId": child, "status": "running"}
        if verb == "chatOrchestration.task":
            task = self.tasks[payload["taskId"]]
            task["status"] = "completed"
            return {"task": copy.deepcopy(task)}
        if verb == "chatOrchestration.tasks.list":
            return {"tasks": list(copy.deepcopy(self.tasks).values())}
        raise AssertionError("Unexpected fixture verb: " + verb)


class ScenarioTests(unittest.TestCase):
    def run_fixture(self, scenario="all", probe=None, *extra):
        probe = probe or FakeRuntimeProbe()
        runner = ScenarioRunner(probe, options(scenario, *extra), clock=probe.clock)
        runner.run()
        return runner.report(), probe

    def test_all_scenarios_pass_with_receipts_transcripts_and_cleanup(self):
        report, probe = self.run_fixture()
        self.assertTrue(report["ok"])
        self.assertEqual(len(report["scenarios"]), 5)
        self.assertTrue(all(snapshot["archived"] for snapshot in probe.snapshots.values()))
        self.assertTrue(all(entry["payload"]["requestId"] for entry in report["mutations"]))
        self.assertEqual(sum(entry.get("replay", False) for entry in report["mutations"]), 4)
        self.assertNotIn(PRIVATE, json.dumps(report))
        self.assertIn("different_project_target", report["scenarios"][3]["checks"])

    def test_failed_turn_and_marker_only_in_user_message_do_not_pass(self):
        for attribute, value, error in [("completed_status", "failed", "without completing"), ("assistant_marker", False, "absent from assistant")]:
            probe = FakeRuntimeProbe()
            setattr(probe, attribute, value)
            report, _ = self.run_fixture("smoke", probe)
            self.assertFalse(report["ok"])
            self.assertIn(error, report["scenarios"][0]["error"])
            self.assertTrue(report["scenarios"][0]["cleanup"][0]["archived"])

    def test_wrong_conflict_code_fails_and_preserves_request_id(self):
        probe = FakeRuntimeProbe()
        probe.conflict_code = "unsupported"
        report, _ = self.run_fixture("queue-idempotency", probe)
        self.assertFalse(report["ok"])
        sends = [entry for entry in report["mutations"] if entry["verb"] == "agentChat.send"]
        self.assertEqual(sends[1]["payload"]["requestId"], sends[2]["payload"]["requestId"])
        self.assertEqual(sends[1]["payload"]["requestId"], sends[3]["payload"]["requestId"])

    def test_queue_race_fails_instead_of_claiming_queue_coverage(self):
        probe = FakeRuntimeProbe()
        probe.queue_busy = False
        report, _ = self.run_fixture("queue-idempotency", probe)
        self.assertFalse(report["ok"])
        self.assertIn("did not enter the real queue", report["scenarios"][0]["error"])

    def test_delegation_to_same_project_fails(self):
        probe = FakeRuntimeProbe()
        probe.second_project = "project-one"
        report, _ = self.run_fixture("cross-project-delegate", probe)
        self.assertFalse(report["ok"])
        self.assertEqual(len(report["scenarios"][0]["cleanup"]), 2)

    def test_mcp_requires_native_tool_item_and_optional_discovery(self):
        probe = FakeRuntimeProbe()
        probe.emit_mcp = False
        report, _ = self.run_fixture("mcp", probe)
        self.assertFalse(report["ok"])
        self.assertIn("native chat_capabilities", report["scenarios"][0]["error"])
        report, _ = self.run_fixture("mcp", None, "--require-tools-list-event")
        self.assertFalse(report["ok"])
        probe = FakeRuntimeProbe()
        probe.emit_discovery = True
        report, _ = self.run_fixture("mcp", probe, "--require-tools-list-event")
        self.assertTrue(report["ok"])

    def test_terminal_timeout_archives_fixture_and_does_not_pass(self):
        probe = FakeRuntimeProbe()
        probe.wait_error = "Chat did not reach a terminal state before the deadline"
        report, _ = self.run_fixture("smoke", probe)
        self.assertFalse(report["ok"])
        self.assertTrue(report["scenarios"][0]["cleanup"][0]["archived"])

    def test_completed_native_tool_with_error_result_does_not_pass(self):
        probe = FakeRuntimeProbe()
        probe.mcp_error = True
        report, _ = self.run_fixture("mcp", probe)
        self.assertFalse(report["ok"])
        self.assertIn("native chat_capabilities", report["scenarios"][0]["error"])

    def test_expired_budget_never_sends_a_mutation(self):
        probe = FakeRuntimeProbe()
        runner = ScenarioRunner(probe, options("smoke"), clock=lambda: 100)
        runner.deadline = 99
        with self.assertRaisesRegex(ProbeError, "deadline exceeded"):
            runner.preflight()
        self.assertFalse(probe.requests)

    def test_cli_sanitizes_report_writes_private_file_and_closes_probe(self):
        probe = FakeRuntimeProbe()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            stdout = io.StringIO()
            with patch("agent_chat_live_scenarios.connect", return_value=probe), redirect_stdout(stdout):
                code = main(["--control-file", "unused", "--workspace-id", "qa-one", "--provider", "codex", "--provider-instance-id", "codex", "--model", "fixture-model", "--scenario", "smoke", "--output", str(output)])
            self.assertEqual(code, 0)
            self.assertTrue(probe.closed)
            self.assertNotIn(PRIVATE, stdout.getvalue())
            self.assertEqual(output.read_text(), stdout.getvalue())
            if os.name == "posix":
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_invalid_cli_values_are_not_echoed(self):
        with redirect_stdout(io.StringIO()), patch("sys.stderr", new=io.StringIO()) as stderr:
            with self.assertRaises(SystemExit):
                options("all", "--run-id", PRIVATE + "!")
            self.assertNotIn(PRIVATE, stderr.getvalue())

    def test_explicit_second_provider_opts_all_into_two_additional_scenarios(self):
        report, probe = self.run_fixture("all", None, *SECOND_PROVIDER)
        self.assertTrue(report["ok"])
        self.assertEqual([item["scenario"] for item in report["scenarios"]][-2:], ["interrupt", "provider-switch"])
        self.assertEqual(len(report["scenarios"]), 7)
        self.assertIn("busy_provider_switch_rejected", report["scenarios"][-2]["checks"])
        self.assertTrue(all(snapshot["archived"] for snapshot in probe.snapshots.values()))

    def test_interrupt_requires_native_active_observation_and_exact_cancelled_status(self):
        report, _ = self.run_fixture("interrupt")
        self.assertTrue(report["ok"])
        evidence = report["scenarios"][0]["evidence"]
        turn_id = evidence["activeTurn"]["session"]["activeTurnId"]
        self.assertEqual(next(turn["status"] for turn in evidence["terminalTurn"]["turns"] if turn["turnId"] == turn_id), "interrupted")
        for attribute, value in (("sustained_race", True), ("interrupt_status", "completed"), ("interrupt_status", "failed"), ("interrupt_status", "running")):
            with self.subTest(attribute=attribute, value=value):
                probe = FakeRuntimeProbe()
                setattr(probe, attribute, value)
                report, _ = self.run_fixture("interrupt", probe)
                self.assertFalse(report["ok"])
                self.assertTrue(report["scenarios"][0]["cleanup"][0]["stopped"])
        probe = FakeRuntimeProbe()
        probe.interrupt_status = "cancelled"
        self.assertTrue(self.run_fixture("interrupt", probe)[0]["ok"])

    def test_busy_switch_requires_the_turn_active_error_code(self):
        probe = FakeRuntimeProbe()
        probe.busy_switch_code = "unsupported"
        report, _ = self.run_fixture("all", probe, *SECOND_PROVIDER)
        self.assertFalse(report["ok"])
        self.assertEqual(report["scenarios"][-1]["scenario"], "interrupt")
        self.assertTrue(report["scenarios"][-1]["cleanup"][0]["archived"])

    def test_provider_switch_recalls_prior_context_without_exposing_it_in_new_prompt(self):
        report, probe = self.run_fixture("provider-switch", None, *SECOND_PROVIDER)
        self.assertTrue(report["ok"])
        evidence = report["scenarios"][0]["evidence"]
        self.assertEqual(evidence["afterSwitch"]["session"]["status"], "starting")
        self.assertEqual(evidence["readyAfterSwitch"]["session"]["status"], "ready")
        self.assertEqual(evidence["beforeSwitch"]["items"], evidence["afterSwitch"]["items"])
        recall = next(payload for verb, payload, _ in probe.requests if verb == "agentChat.send" and payload["clientMessageId"].endswith("-recall"))
        self.assertNotIn("QA_PUBLIC_CONTEXT_fixture", recall["text"])
        self.assertEqual(evidence["recallCompleted"]["turns"][-1]["provider"], "grok")

    def test_handoff_requires_snapshot_envelope_identity_generation_and_history(self):
        for fault in ("envelope", "tab", "generation", "history"):
            with self.subTest(fault=fault):
                probe = FakeRuntimeProbe()
                probe.configure_fault = fault
                report, _ = self.run_fixture("provider-switch", probe, *SECOND_PROVIDER)
                self.assertFalse(report["ok"])
                self.assertTrue(report["scenarios"][0]["cleanup"][0]["archived"])

    def test_handoff_rejects_missing_context_wrong_provider_and_unready_session(self):
        for attribute in ("handoff", "wrong_recall_provider", "switch_ready"):
            with self.subTest(attribute=attribute):
                probe = FakeRuntimeProbe()
                setattr(probe, attribute, attribute == "wrong_recall_provider")
                report, _ = self.run_fixture("provider-switch", probe, *SECOND_PROVIDER)
                self.assertFalse(report["ok"])
                self.assertTrue(report["scenarios"][0]["cleanup"][0]["stopped"])

    def test_failed_second_provider_preflight_never_mutates(self):
        probe = FakeRuntimeProbe()
        probe.second_available = False
        runner = ScenarioRunner(probe, options("all", *SECOND_PROVIDER), clock=probe.clock)
        with self.assertRaisesRegex(ProbeError, "not available"):
            runner.run()
        self.assertEqual([verb for verb, _, _ in probe.requests], ["agentChat.providers"])
        self.assertFalse(runner.mutations)
        self.assertFalse(probe.snapshots)

    def test_rpc_and_snapshot_budgets_remain_individual_during_terminal_polling(self):
        probe = FakeRuntimeProbe()
        probe.interrupt_status = "running"
        report, _ = self.run_fixture("interrupt", probe, "--timeout", "1", "--request-timeout", "0.1")
        self.assertFalse(report["ok"])
        self.assertGreater(len(probe.snapshot_timeouts), 3)
        self.assertTrue(all(0 < timeout <= 0.1 for timeout in probe.snapshot_timeouts))
        self.assertTrue(all(0 < timeout <= 0.1 for _, _, timeout in probe.requests))
        self.assertLessEqual(probe.clock.value, 101)

    def test_cleanup_rejects_archived_chat_with_live_or_streaming_state(self):
        for fault in ("status", "active", "queue", "pendingRequests", "streaming"):
            with self.subTest(fault=fault):
                probe = FakeRuntimeProbe()
                probe.cleanup_fault = fault
                report, _ = self.run_fixture("smoke", probe)
                self.assertFalse(report["ok"])
                self.assertIn("cleanup", report["scenarios"][0])
                self.assertIn("empty state", report["scenarios"][0]["cleanup"][0]["error"])

    def test_mcp_uses_reported_server_without_inventing_hidden_metadata(self):
        probe = FakeRuntimeProbe()
        probe.mcp_server = "other-server"
        self.assertFalse(self.run_fixture("mcp", probe)[0]["ok"])
        probe = FakeRuntimeProbe()
        probe.mcp_server = None
        self.assertTrue(self.run_fixture("mcp", probe)[0]["ok"])

    def test_second_provider_options_require_explicit_switch_scope(self):
        for scenario, extra in (("provider-switch", ()), ("all", ("--second-provider", "grok")), ("smoke", SECOND_PROVIDER)):
            with self.subTest(scenario=scenario), patch("sys.stderr", new=io.StringIO()):
                with self.assertRaises(SystemExit):
                    options(scenario, *extra)

    def test_output_write_failure_fails_run_and_still_closes_probe(self):
        probe = FakeRuntimeProbe()
        with tempfile.TemporaryDirectory() as directory, patch("agent_chat_live_scenarios.connect", return_value=probe), patch("sys.stderr", new=io.StringIO()), redirect_stdout(io.StringIO()):
            code = main(["--control-file", "unused", "--workspace-id", "qa-one", "--provider", "codex", "--provider-instance-id", "codex", "--scenario", "smoke", "--output", directory])
        self.assertEqual(code, 1)
        self.assertTrue(probe.closed)
        self.assertTrue(all(snapshot["archived"] for snapshot in probe.snapshots.values()))


if __name__ == "__main__":
    unittest.main()
