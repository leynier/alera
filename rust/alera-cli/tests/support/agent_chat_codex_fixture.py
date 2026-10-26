#!/usr/bin/env python3
"""Deterministic Codex JSONL peer. Uses no SDK, network, credentials, or model."""

import json
import os
import sys


def record(value):
    with open(os.environ["ALERA_CHAT_FIXTURE_LOG"], "a", encoding="utf-8") as log:
        log.write(json.dumps(dict(value, pid=os.getpid())) + "\n")


def emit(value):
    sys.stdout.write(json.dumps(value) + "\n")
    sys.stdout.flush()


def notice(method, params):
    emit({"method": method, "params": params})


def complete(thread, turn, item, status="completed"):
    notice("item/completed", {
        "threadId": thread,
        "turnId": turn,
        "item": {"id": item, "type": "agentMessage", "status": "completed",
                 "text": "Fixture response."},
    })
    notice("turn/completed", {
        "threadId": thread,
        "turn": {"id": turn, "status": status},
    })


arguments = sys.argv[1:]
if arguments in (["--version"], ["debug", "models"]):
    record({"event": "metadata_probe", "args": arguments,
            "credentialPath": os.environ.get("ALERA_CHAT_CREDENTIAL_FILE")})
    if arguments == ["--version"]:
        sys.stdout.write("codex-cli 1.2.3\n")
    else:
        sys.stdout.write('{"models": []}\n')
    sys.stdout.flush()
    sys.exit(0)
if arguments != ["app-server"]:
    record({"event": "unexpected_command", "args": arguments})
    raise RuntimeError("unsupported fixture command: %r" % arguments)

record({"event": "started", "args": arguments, "cwd": os.getcwd(),
        "credentialPath": os.environ.get("ALERA_CHAT_CREDENTIAL_FILE"),
        "originator": os.environ.get("CODEX_INTERNAL_ORIGINATOR_OVERRIDE")})
thread = "fixture-thread-" + str(os.getpid())
turn_number = 0
pending = None
initialized = False

try:
    for line in sys.stdin:
        message = json.loads(line)
        record({"event": "input", "message": message})
        method = message.get("method")
        request_id = message.get("id")
        params = message.get("params", {})

        if method == "initialize":
            emit({"id": request_id, "result": {
                "codexHome": os.environ["HOME"], "platformFamily": "unix",
                "platformOs": sys.platform, "userAgent": "alera-host-fixture",
            }})
        elif method == "initialized":
            initialized = True
        elif method in ("thread/start", "thread/resume"):
            if not initialized:
                raise RuntimeError("thread started before initialized notification")
            thread = params.get("threadId", thread)
            emit({"id": request_id, "result": {"thread": {"id": thread}}})
        elif method == "skills/list":
            emit({"id": request_id, "result": {"data": [
                {"cwd": cwd, "errors": [], "skills": []} for cwd in params.get("cwds", [])
            ]}})
        elif method == "turn/start":
            if pending is not None:
                raise RuntimeError("another turn started during approval")
            turn_number += 1
            turn = "fixture-turn-%s-%s" % (os.getpid(), turn_number)
            item = "fixture-assistant-" + turn
            emit({"id": request_id, "result": {"turn": {"id": turn}}})
            notice("turn/started", {"threadId": thread, "turn": {"id": turn}})
            notice("item/started", {
                "threadId": thread, "turnId": turn,
                "item": {"id": item, "type": "agentMessage", "status": "inProgress"},
            })
            for delta in ("Fixture ", "response."):
                notice("item/agentMessage/delta", {
                    "threadId": thread, "turnId": turn, "itemId": item, "delta": delta,
                })
            text = " ".join(part.get("text", "") for part in params.get("input", []))
            if text == "approval":
                pending = (thread, turn, item)
                emit({"id": 7001, "method": "item/commandExecution/requestApproval",
                      "params": {"threadId": thread, "turnId": turn,
                                 "itemId": "fixture-command", "command": "printf fixture",
                                 "reason": "Fixture approval boundary"}})
            else:
                complete(thread, turn, item)
        elif method == "turn/interrupt":
            emit({"id": request_id, "result": {}})
            if pending is not None:
                complete(*pending, status="interrupted")
                pending = None
        elif method == "feedback/upload":
            if params.get("reason") == "fail":
                emit({"id": request_id, "error": {
                    "code": -32603, "message": "Fixture feedback upload refused."}})
            else:
                emit({"id": request_id, "result": {
                    "threadId": "fixture-feedback-" + params["threadId"]}})
        elif method is None and request_id == 7001:
            if pending is None or message.get("result", {}).get("decision") != "accept":
                raise RuntimeError("unexpected native approval response")
            complete(*pending)
            pending = None
        else:
            raise RuntimeError("unsupported fixture method: %r" % method)
finally:
    record({"event": "exited"})
