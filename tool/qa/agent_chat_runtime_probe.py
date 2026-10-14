#!/usr/bin/env python3
"""Explicit QA RPCs to an already-running Alera host; no host lifecycle control."""

import argparse
from collections import deque
import json
import math
import os
from pathlib import Path
import re
import socket
import sys
import time

PROTOCOL_VERSION = 5
CAPABILITIES = ["agentChatV1", "chatOrchestrationV1"]
MAX_FRAME_BYTES = 16 * 1024 * 1024
REDACTED = "[REDACTED]"
TERMINAL_TURN_STATES = {"completed", "failed", "interrupted", "cancelled"}


class ProbeError(Exception):
    report = None


class Redactor:
    """Redact at the output boundary, including repeated secrets in prose."""

    def __init__(self):
        self.secrets = set()

    @staticmethod
    def sensitive(key):
        key = re.sub(r"[^a-z0-9]", "", key.lower())
        return key in {"env", "environment", "processenvironment", "shellenvironment"} or bool(
            re.search(r"token$|secret|password|credential|authorization|authentication|apikey|privatekey|cookie", key)
        )

    def register(self, value):
        if isinstance(value, str) and value:
            self.secrets.add(value)
        elif isinstance(value, dict):
            for item in value.values():
                self.register(item)
        elif isinstance(value, list):
            for item in value:
                self.register(item)

    def discover(self, value):
        if isinstance(value, dict):
            if any(isinstance(value.get(key), str) and self.sensitive(value[key]) for key in ("name", "key", "variable")):
                self.register(value.get("value"))
            for key, item in value.items():
                if self.sensitive(key):
                    self.register(item)
                else:
                    self.discover(item)
        elif isinstance(value, list):
            for item in value:
                self.discover(item)

    def text(self, value):
        for secret in sorted(self.secrets, key=len, reverse=True):
            if len(secret) < 4:
                value = re.sub(r"(?<![A-Za-z0-9])" + re.escape(secret) + r"(?![A-Za-z0-9])", REDACTED, value)
            else:
                value = value.replace(secret, REDACTED)
        value = re.sub(r"(?i)\b(Bearer|Basic)\s+[^\s\"',;]+", r"\1 [REDACTED]", value)
        value = re.sub(r"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]+)\b", REDACTED, value)
        value = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", REDACTED, value)
        value = re.sub(r"(?i)((?:token|secret|password|credential|api[_-]?key|authorization|cookie)[\"']?\s*[=:]\s*)(?:\"[^\"]*\"|'[^']*'|[^\s,;\"']+)", r"\1[REDACTED]", value)
        value = re.sub(r"\b([A-Z][A-Z0-9_]{2,}=)(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)", r"\1[REDACTED]", value)
        value = re.sub(r"(?i)(https?://)[^/\s:@]+:[^/\s@]+@", r"\1[REDACTED]@", value)
        value = re.sub(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", REDACTED, value, flags=re.DOTALL)
        return value

    def clean(self, value):
        self.discover(value)
        return self._clean(value)

    def _clean(self, value):
        if isinstance(value, dict):
            return {self.text(key): REDACTED if self.sensitive(key) and not isinstance(item, bool) else self._clean(item) for key, item in value.items()}
        if isinstance(value, (list, tuple, deque)):
            return [self._clean(item) for item in value]
        return self.text(value) if isinstance(value, str) else value


def read_json(path):
    try:
        with Path(path).expanduser().open("rb") as source:
            raw = source.read(MAX_FRAME_BYTES + 1)
        if len(raw) > MAX_FRAME_BYTES:
            raise ProbeError("JSON input exceeds the size limit")
        return json.loads(raw)
    except (OSError, UnicodeError, ValueError):
        raise ProbeError("Could not read a valid JSON input file") from None


class RuntimeProbe:
    def __init__(self, control_file, timeout=30, max_events=10000, max_event_bytes=32 * 1024 * 1024, redactor=None):
        self.timeout = timeout
        self.redactor = redactor if redactor is not None else Redactor()
        self.events = deque()
        self.events_seen = self.events_dropped = self.event_bytes = 0
        self.max_events, self.max_event_bytes = max_events, max_event_bytes
        self.responses = []
        self.snapshots = {}
        self.buffer = bytearray()
        self.next_id = 1
        self.sock = None
        control = read_json(control_file)
        self.redactor.discover(control)
        if not isinstance(control, dict) or control.get("protocolVersion") != PROTOCOL_VERSION:
            raise ProbeError("Control file has an incompatible protocol version")
        token, port = control.get("token"), control.get("port")
        if not isinstance(token, str) or not token or type(port) is not int or not 0 < port < 65536:
            raise ProbeError("Control file lacks valid local connection metadata")
        self.redactor.register(token)
        for key, value in os.environ.items():
            if self.redactor.sensitive(key):
                self.redactor.register(value)
        self.metadata = {"protocolVersion": PROTOCOL_VERSION, "port": port, "pid": control.get("pid"), "runtimeCapabilities": control.get("runtimeCapabilities", [])}
        try:
            self.sock = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        except OSError as error:
            raise ProbeError("Local host connection failed (errno %s)" % error.errno) from None
        try:
            self.request("hello", {"protocolVersion": PROTOCOL_VERSION, "token": token, "clientKind": "cli", "sharedCheckoutWorkspacesV1": True, "supportedTabKinds": ["agentChat"], "capabilities": CAPABILITIES})
        except ProbeError as error:
            error.report = self.report()
            self.close()
            raise
        except Exception:
            self.close()
            raise

    def close(self):
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()

    def _frame(self, deadline):
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                if newline > MAX_FRAME_BYTES:
                    raise ProbeError("Host frame exceeds the size limit")
                raw = bytes(self.buffer[:newline])
                del self.buffer[:newline + 1]
                try:
                    frame = json.loads(raw)
                except (UnicodeError, ValueError):
                    raise ProbeError("Host returned an invalid JSON frame") from None
                if not isinstance(frame, dict):
                    raise ProbeError("Host returned a non-object frame")
                self.redactor.discover(frame)
                return frame
            if len(self.buffer) > MAX_FRAME_BYTES:
                raise ProbeError("Host frame exceeds the size limit")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError
            self.sock.settimeout(remaining)
            try:
                data = self.sock.recv(65536)
            except socket.timeout:
                raise TimeoutError from None
            except OSError as error:
                raise ProbeError("Host read failed (errno %s)" % error.errno) from None
            if not data:
                raise ProbeError("Host closed the connection")
            self.buffer.extend(data)

    def _event(self, frame):
        size = len(json.dumps(frame, ensure_ascii=False).encode("utf-8"))
        self.events_seen += 1
        while self.events and (len(self.events) >= self.max_events or self.event_bytes + size > self.max_event_bytes):
            self.event_bytes -= self.events.popleft()[0]
            self.events_dropped += 1
        if self.max_events and size <= self.max_event_bytes:
            self.events.append((size, frame))
            self.event_bytes += size
        else:
            self.events_dropped += 1

    def request(self, verb, payload, timeout=None, record=True):
        if verb != "hello" and not verb.startswith(("agentChat.", "chatOrchestration.")):
            raise ProbeError("Probe accepts only agentChat.* and chatOrchestration.* requests")
        self.redactor.discover(payload)
        request_id = self.next_id
        self.next_id += 1
        raw = json.dumps({"id": request_id, "type": verb, "payload": payload}, ensure_ascii=False).encode("utf-8") + b"\n"
        if len(raw) > MAX_FRAME_BYTES:
            raise ProbeError("Request exceeds the size limit")
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        self.sock.settimeout(max(0.001, deadline - time.monotonic()))
        try:
            self.sock.sendall(raw)
            while True:
                frame = self._frame(deadline)
                if frame.get("event") is not None:
                    self._event(frame)
                elif frame.get("id") == request_id:
                    if record or frame.get("ok") is not True:
                        self.responses.append({"verb": verb, "response": frame})
                    if frame.get("ok") is not True:
                        raise ProbeError("Host rejected %s; inspect the sanitized response" % verb)
                    return frame.get("payload")
        except TimeoutError:
            raise ProbeError("Timed out waiting for %s" % verb) from None
        except OSError as error:
            raise ProbeError("Host write failed (errno %s)" % error.errno) from None

    def collect(self, seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                frame = self._frame(deadline)
            except TimeoutError:
                break
            if frame.get("event") is not None:
                self._event(frame)

    def snapshot(self, chat_id, timeout=None):
        snapshot = self.request("agentChat.snapshot", {"chatId": chat_id}, timeout, record=False)
        if not isinstance(snapshot, dict):
            raise ProbeError("Host returned an invalid chat snapshot")
        self.snapshots[chat_id] = snapshot
        return snapshot

    def wait_terminal(self, chat_id, timeout=None, turn_id=None, poll_interval=0.25):
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        while time.monotonic() < deadline:
            snapshot = self.snapshot(chat_id, max(0.001, deadline - time.monotonic()))
            session = snapshot.get("session", {})
            turns = snapshot.get("turns", [])
            if turn_id:
                done = any(turn.get("turnId") == turn_id and turn.get("status") in TERMINAL_TURN_STATES for turn in turns)
            else:
                done = bool(session) and not session.get("activeTurnId") and session.get("status") not in {"starting", "running", "waiting"} and not snapshot.get("queue") and not snapshot.get("pendingRequests") and all(turn.get("status") in TERMINAL_TURN_STATES for turn in turns)
            if done:
                return snapshot
            self.collect(min(poll_interval, max(0, deadline - time.monotonic())))
        raise ProbeError("Chat did not reach a terminal state before the deadline")

    def report(self):
        return self.redactor.clean({"host": self.metadata, "responses": self.responses, "events": [frame for _, frame in self.events], "eventsSeen": self.events_seen, "eventsDropped": self.events_dropped, "snapshots": self.snapshots, "turnStates": {chat_id: {"session": snapshot.get("session", {}), "turns": snapshot.get("turns", []), "pendingRequestCount": len(snapshot.get("pendingRequests", [])), "queueCount": len(snapshot.get("queue", []))} for chat_id, snapshot in self.snapshots.items()}})


class PrivateArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(2, "Invalid probe arguments; use --help.\n")


def arguments():
    parser = PrivateArgumentParser(description=__doc__)
    location = parser.add_mutually_exclusive_group(required=True)
    location.add_argument("--control-file", help="Explicit QA host control JSON path")
    location.add_argument("--runtime-dir", help="Explicit QA runtime directory; tries host.json, then runtime-host.json")
    parser.add_argument("--verb", required=True, help="One explicit agentChat.* or chatOrchestration.* verb")
    payload = parser.add_mutually_exclusive_group()
    payload.add_argument("--payload", default=None, help="JSON object; prefer a file for private content")
    payload.add_argument("--payload-file", help="Path to a JSON object")
    parser.add_argument("--timeout", type=float, default=30, help="Request and terminal-wait deadlines in seconds (default: 30)")
    parser.add_argument("--collect-seconds", type=float, default=0, help="Collect unsolicited events after the explicit request")
    parser.add_argument("--snapshot-chat", action="append", default=[], help="Also snapshot this chat ID; repeatable")
    parser.add_argument("--no-auto-snapshot", action="store_true", help="Do not infer a snapshot chat ID from the request/response")
    parser.add_argument("--wait-terminal", action="store_true", help="Poll selected chat snapshots until terminal; never answers requests")
    parser.add_argument("--turn-id", help="Wait for this turn specifically; requires one selected chat")
    parser.add_argument("--max-events", type=int, default=10000)
    parser.add_argument("--max-event-bytes", type=int, default=32 * 1024 * 1024)
    parser.add_argument("--diagnostics-file", action="append", default=[], help="Add a redacted 64 KiB log tail; repeatable")
    parser.add_argument("--output", help="Also write sanitized JSON to a private file")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0 or not math.isfinite(args.collect_seconds) or args.collect_seconds < 0 or args.max_events < 0 or args.max_event_bytes < 0 or (args.turn_id and not args.wait_terminal):
        parser.error("Invalid limits")
    return args


def diagnostics(paths, redactor):
    tails = []
    for path in paths:
        try:
            with Path(path).expanduser().open("rb") as source:
                source.seek(0, os.SEEK_END)
                source.seek(max(0, source.tell() - 65536))
                lines = source.read().decode("utf-8", errors="replace").splitlines()
            values = []
            for line in lines:
                try:
                    values.append(json.loads(line))
                except ValueError:
                    values.append(line)
            tails.append({"source": Path(path).name, "tail": values})
        except OSError:
            tails.append({"source": Path(path).name, "error": "Could not read diagnostics file"})
    return redactor.clean(tails)


def main():
    args = arguments()
    probe = None
    redactor = Redactor()
    report = {"ok": False}
    try:
        payload = read_json(args.payload_file) if args.payload_file else json.loads(args.payload or "{}")
        if not isinstance(payload, dict):
            raise ProbeError("Request payload must be a JSON object")
        redactor.discover(payload)
        controls = [Path(args.control_file).expanduser()] if args.control_file else [path for path in [Path(args.runtime_dir).expanduser() / "host.json", Path(args.runtime_dir).expanduser() / "runtime-host.json"] if path.is_file()]
        if not controls:
            raise ProbeError("No control file exists in the explicit QA runtime directory")
        last_error = None
        for control in controls:
            try:
                probe = RuntimeProbe(control, args.timeout, args.max_events, args.max_event_bytes, redactor)
                break
            except ProbeError as error:
                last_error = error
        if probe is None:
            raise last_error
        redactor = probe.redactor
        response = probe.request(args.verb, payload)
        probe.collect(args.collect_seconds)
        chat_ids = list(args.snapshot_chat)
        if not args.no_auto_snapshot:
            for candidate in [payload.get("chatId"), response.get("chatId") if isinstance(response, dict) else None]:
                if isinstance(candidate, str) and candidate:
                    chat_ids.append(candidate)
        chat_ids = list(dict.fromkeys(chat_ids))
        if args.wait_terminal and (not chat_ids or (args.turn_id and len(chat_ids) != 1)):
            raise ProbeError("Terminal wait requires selected chat IDs; a turn-specific wait requires exactly one")
        for chat_id in chat_ids:
            if args.wait_terminal:
                probe.wait_terminal(chat_id, turn_id=args.turn_id)
            else:
                probe.snapshot(chat_id)
        report["ok"] = True
    except (ValueError, UnicodeError):
        report["error"] = "Invalid JSON request payload"
    except ProbeError as error:
        report["error"] = str(error)
        if error.report:
            report.update(error.report)
    except KeyboardInterrupt:
        report["error"] = "Probe interrupted"
    except Exception as error:
        report["error"] = "Probe failed (%s); raw exception details suppressed" % type(error).__name__
    finally:
        if probe is not None:
            report.update(probe.report())
            probe.close()
    report["diagnostics"] = diagnostics(args.diagnostics_file, redactor)
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
