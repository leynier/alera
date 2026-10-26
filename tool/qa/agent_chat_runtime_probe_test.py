"""Offline framing/auth/redaction checks; never connects to an Alera profile."""

from contextlib import contextmanager
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from agent_chat_runtime_probe import CAPABILITIES, ProbeError, Redactor, RuntimeProbe

TOKEN = "qa-fixture-token-private"


@contextmanager
def fixture(handler):
    errors = []
    requests = []
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(3)

    def serve():
        try:
            connection, _ = server.accept()
            with connection, connection.makefile("rb") as reader:
                connection.settimeout(3)
                for line in reader:
                    request = json.loads(line)
                    requests.append(request)
                    if not handler(connection, request):
                        break
        except Exception as error:
            errors.append(error)

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    with tempfile.TemporaryDirectory() as directory:
        control = Path(directory) / "host.json"
        control.write_text(json.dumps({"protocolVersion": 5, "port": server.getsockname()[1], "token": TOKEN, "runtimeCapabilities": CAPABILITIES}), encoding="utf-8")
        try:
            yield control, requests
        finally:
            server.close()
            worker.join(4)
            if worker.is_alive():
                raise AssertionError("Fixture socket worker did not stop")
            if errors:
                raise errors[0]


def send(connection, request, payload=None, ok=True):
    connection.sendall((json.dumps({"id": request["id"], "ok": ok, "payload": payload}) + "\n").encode())


class ProbeTests(unittest.TestCase):
    def test_authenticated_cli_and_fragmented_unicode_events(self):
        def handler(connection, request):
            if request["type"] == "hello":
                self.assertEqual(request["payload"], {"protocolVersion": 5, "token": TOKEN, "clientKind": "cli", "sharedCheckoutWorkspacesV1": True, "supportedTabKinds": ["agentChat"], "capabilities": CAPABILITIES})
                send(connection, request, {"token": TOKEN})
            else:
                event = (json.dumps({"event": "agentChatChanged", "payload": {"text": "hé " + TOKEN}}, ensure_ascii=False) + "\n").encode()
                split = event.index("é".encode()) + 1
                connection.sendall(event[:split])
                time.sleep(0.01)
                connection.sendall(event[split:])
                send(connection, request, {"providers": []})
            return True

        with fixture(handler) as (control, _), RuntimeProbe(control, timeout=1) as probe:
            probe.request("agentChat.providers", {})
            report = probe.report()
            self.assertEqual(report["eventsSeen"], 1)
            self.assertEqual(report["events"][0]["payload"]["text"], "hé [REDACTED]")
            self.assertNotIn(TOKEN, json.dumps(report))

    def test_terminal_wait_reads_persisted_snapshot_and_keeps_latest(self):
        reads = []

        def handler(connection, request):
            if request["type"] == "hello":
                send(connection, request, {})
            else:
                reads.append(request)
                busy = len(reads) == 1
                send(connection, request, {"chatId": "c", "session": {"status": "running" if busy else "ready", "activeTurnId": "t" if busy else None}, "turns": [{"turnId": "t", "status": "running" if busy else "completed"}], "items": []})
            return True

        with fixture(handler) as (control, _), RuntimeProbe(control, timeout=1) as probe:
            snapshot = probe.wait_terminal("c", poll_interval=0.01)
            self.assertEqual(snapshot["turns"][0]["status"], "completed")
            self.assertEqual(len(reads), 2)
            self.assertEqual(len(probe.report()["responses"]), 1)
            self.assertEqual(probe.report()["turnStates"]["c"]["queueCount"], 0)

    def test_observation_timeout_and_event_capture_bounds(self):
        def handler(connection, request):
            send(connection, request, {})
            if request["type"] != "hello":
                for index in range(3):
                    connection.sendall((json.dumps({"event": "changed", "payload": {"index": index}}) + "\n").encode())
            return True

        with fixture(handler) as (control, _), RuntimeProbe(control, timeout=1, max_events=1) as probe:
            probe.request("agentChat.providers", {})
            probe.collect(0.05)
            report = probe.report()
            self.assertEqual(report["eventsSeen"], 3)
            self.assertEqual(report["eventsDropped"], 2)
            self.assertEqual(report["events"][0]["payload"]["index"], 2)
            with self.assertRaises(ProbeError):
                probe.request("host.shutdown", {})

    def test_redacts_nested_fields_repeated_secrets_and_plaintext_diagnostics(self):
        redactor = Redactor()
        value = {"message": "use private-example or Bearer unknown-key; PATH=/private/path", "env": {"THING": "private-example"}, "nested": {"apiKey": "private-key"}, "entry": {"name": "OPENAI_API_KEY", "value": "abc"}, "again": "secret is abc", "usage": {"inputTokens": 22}, "text": '{"token":"unregistered-token"} token="quoted-key with spaces"', "pem": "-----BEGIN PRIVATE KEY-----\nprivate material\n-----END PRIVATE KEY-----"}
        report = redactor.clean(value)
        self.assertEqual(report["env"], "[REDACTED]")
        self.assertEqual(report["usage"]["inputTokens"], 22)
        for secret in ["private-example", "private-key", "unknown-key", "/private/path", "unregistered-token", "quoted-key", "with spaces", "private material", "abc"]:
            self.assertNotIn(secret, json.dumps(report))

    def test_request_deadline_is_bounded(self):
        def handler(connection, request):
            if request["type"] == "hello":
                send(connection, request, {})
            else:
                time.sleep(0.1)
            return True

        with fixture(handler) as (control, _), RuntimeProbe(control, timeout=0.05) as probe:
            with self.assertRaisesRegex(ProbeError, "Timed out waiting"):
                probe.request("agentChat.providers", {})

    def test_runtime_directory_falls_back_after_stale_control(self):
        def handler(connection, request):
            send(connection, request, {})
            return True

        with fixture(handler) as (control, _):
            runtime_control = control.with_name("runtime-host.json")
            control.rename(runtime_control)
            control.write_text('{"protocolVersion":4,"token":"stale-private-token","port":1}', encoding="utf-8")
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("agent_chat_runtime_probe.py")), "--runtime-dir", str(control.parent), "--verb", "chatOrchestration.capabilities"], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            self.assertTrue(json.loads(result.stdout)["ok"])
            self.assertNotIn("stale-private-token", result.stdout + result.stderr)

    def test_cli_sanitizes_rejected_response_and_writes_private_output(self):
        def handler(connection, request):
            if request["type"] == "hello":
                send(connection, request, {})
                return True
            connection.sendall((json.dumps({"id": request["id"], "ok": False, "error": "denied " + TOKEN, "payload": {"credential": "private-credential"}}) + "\n").encode())
            return False

        with fixture(handler) as (control, _):
            output = control.parent / "report.json"
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("agent_chat_runtime_probe.py")), "--control-file", str(control), "--verb", "agentChat.send", "--payload", '{"chatId":"c"}', "--output", str(output)], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertFalse(json.loads(result.stdout)["ok"])
            self.assertNotIn(TOKEN, result.stdout + result.stderr)
            self.assertNotIn("private-credential", result.stdout)
            self.assertEqual(output.read_text(encoding="utf-8"), result.stdout)
            if os.name == "posix":
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
