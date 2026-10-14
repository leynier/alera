# Agent Chat Runtime Probe

`agent_chat_runtime_probe.py` connects to an explicitly selected, already-running QA runtime on `127.0.0.1`. It uses the protocolVersion 5 JSON Lines contract from `rust/alera-cli/src/runtime_host_client.rs` and `rust/alera-cli/tests/support/agent_chat_socket_host.rs`. It authenticates as a CLI with `agentChatV1`, `chatOrchestrationV1`, and the `agentChat` tab kind. It never starts or stops a host, installs dependencies, or runs inference by itself. Only the supplied `agentChat.*` or `chatOrchestration.*` request can mutate runtime state or launch provider work; optional polling only reads chat snapshots.

```sh
python3 tool/qa/agent_chat_runtime_probe.py --runtime-dir /path/to/isolated-qa-runtime --verb agentChat.providers --output /path/to/providers.json
python3 tool/qa/agent_chat_runtime_probe.py --control-file /path/to/isolated-qa-runtime/host.json --verb chatOrchestration.capabilities --payload-file /path/to/capabilities-request.json
python3 tool/qa/agent_chat_runtime_probe.py --runtime-dir /path/to/isolated-qa-runtime --verb agentChat.send --payload-file /path/to/explicit-send-request.json --wait-terminal --timeout 180 --output /path/to/turn.json
python3 tool/qa/agent_chat_runtime_probe.py --runtime-dir /path/to/isolated-qa-runtime --verb agentChat.snapshot --payload '{"chatId":"CHAT_ID"}' --collect-seconds 2 --diagnostics-file /path/to/qa-runtime/logs/runtime.jsonl
```

`--payload-file` accepts a JSON object with the verb's actual wire fields, including caller-selected request or message IDs. The probe never invents IDs inside payloads or retries mutation requests. `--timeout` bounds each response and each chat's terminal wait. `--collect-seconds` adds a bounded event window after the explicit response. The input or response's top-level `chatId` selects a final snapshot automatically; use repeatable `--snapshot-chat` for other chats or `--no-auto-snapshot` to disable inference. `--wait-terminal` requires a selected chat and waits until it has no active turn, queue, or pending request, and all observed turns have terminal statuses. It reports failed and interrupted turns as terminal too; inspect `turnStates` to assert the desired outcome. `--turn-id` waits for one particular turn and requires exactly one selected chat. The probe never answers an approval or elicitation while waiting.

Output contains sanitized responses, ordered events, final persisted snapshots, and turn states. `eventsDropped` records when the default 10,000-event or 32 MiB capture limit discarded old events; adjust `--max-events` and `--max-event-bytes` explicitly if needed. JSON input and individual frames are capped at 16 MiB. Diagnostics are optional redacted 64 KiB file tails. The output sink suppresses environment and credential fields, the privately read control token, repeated secrets discovered in sensitive fields, sensitive environment values, and common credential patterns in prose. It never emits the raw control file or raw exception detail. `--output` additionally writes the report with mode `0600`. Exit status is zero when requested operations and waits succeed, one for rejected requests/timeouts/output failure, and two for invalid CLI arguments.

For procedural QA, import `RuntimeProbe` and use it as a context manager: `RuntimeProbe(control_file, timeout=180)`, `request(verb, payload)`, `collect(seconds)`, `snapshot(chat_id)`, `wait_terminal(chat_id, timeout=180, turn_id=None)`, and `report()`. `report()` is sanitized; returned request/snapshot values remain in-memory wire data for scenario assertions and must not be printed directly.

```sh
python3 tool/qa/agent_chat_runtime_probe_test.py
```

The seven standard-library fixture tests exercise authenticated hello, fragmented UTF-8 JSONL events, persisted terminal polling, request/observation deadlines, stale control-file fallback, event bounds, redaction, rejected responses, and private output permissions. They only connect to ephemeral fixture sockets, never to an Alera profile or provider.

## Agent Chat Live Scenarios

`agent_chat_live_scenarios.py` runs procedural acceptance scenarios through `RuntimeProbe` against an explicitly selected, already-running QA runtime and existing fixture workspaces. Executing it creates chats and sends real inference requests to the explicitly selected installed provider account. It does not create workspaces, manage the host lifecycle, edit repository files, answer approvals, or read credential files. Run it only after selecting isolated QA fixtures and authorizing provider usage.

```sh
python3 tool/qa/agent_chat_live_scenarios.py --runtime-dir /path/to/isolated-qa-runtime --workspace-id QA_WORKSPACE_ID --provider codex --provider-instance-id codex --model REPORTED_MODEL_ID --scenario smoke --output /path/to/qa-smoke.json
python3 tool/qa/agent_chat_live_scenarios.py --control-file /path/to/isolated-qa-runtime/host.json --workspace-id QA_WORKSPACE_ID --second-workspace-id OTHER_PROJECT_QA_WORKSPACE_ID --provider codex --provider-instance-id codex --model REPORTED_MODEL_ID --scenario all --timeout 180 --output /path/to/qa-all.json
python3 tool/qa/agent_chat_live_scenarios.py --runtime-dir /path/to/isolated-qa-runtime --workspace-id QA_WORKSPACE_ID --provider codex --provider-instance-id codex --scenario interrupt --timeout 180 --request-timeout 30 --output /path/to/qa-interrupt.json
python3 tool/qa/agent_chat_live_scenarios.py --runtime-dir /path/to/isolated-qa-runtime --workspace-id QA_WORKSPACE_ID --provider codex --provider-instance-id codex --second-provider grok --second-provider-instance-id grok --scenario provider-switch --timeout 180 --request-timeout 30 --output /path/to/qa-provider-switch.json
python3 tool/qa/agent_chat_live_scenarios_test.py
```

1. `smoke` creates a chat, sends a unique marker prompt, and requires a completed turn with that marker in assistant output for the exact client message.
2. `queue-idempotency` sends two messages immediately, requires the second to actually enter the queue, replays its same request, checks a changed payload returns `request_conflict`, and requires exactly two completed turns with one persisted user message each. If the first turn finishes before the second is admitted, this scenario fails with an explicit queue-coverage error.
3. `archive-reopen` completes a smoke turn, archives and reopens the same chat in a new tab, and compares persisted transcript fields and turn history before and after both operations.
4. `cross-project-delegate` delegates into `--second-workspace-id`, checks same-request replay and differing-payload conflict, then requires a completed task and child turn with the marker. It compares actual project IDs from the primary chat and delegated task, so two workspaces in the same project do not pass.
5. `mcp` checks advertised orchestration support, asks the provider to discover the injected `alera` server's actual tools and call `chat_capabilities`, and requires a completed native tool item for that call without a reported error. When the native item reports a server name, it must be `alera`. Assistant prose alone never passes. `tools_list` is a provider discovery tool, while the MCP wire discovery method is `tools/list`; neither is an Alera chat tool. Discovery may not produce a transcript item, so its evidence is reported separately. Add `--require-tools-list-event` for providers that expose discovery as a native tool event. The runner does not invent a provider-hidden discovery event or assume a capability result schema.
6. `interrupt` completes a warmup turn, requests sustained text without tools or file changes, and observes native assistant or reasoning text for the exact active turn before interrupting it. It requires that turn's persisted `interrupted` or `cancelled` status, settled items, and an idle native `ready` session with no queue or requests. An acknowledgement alone cannot pass, and a turn that finishes before observation fails with an explicit coverage error. Native active observation is bounded to 30 seconds and interruption settlement to 60 seconds within the scenario deadline.
7. `provider-switch` completes a seed turn containing a unique public QA reference phrase, switches the idle chat to an explicitly requested second provider, and verifies the `{snapshot}` envelope, unchanged chat/tab identity and prior history, and one generation increment. It waits up to 60 seconds for native idle readiness, then asks the second provider to recall the phrase without putting it in the new prompt. The new turn must complete with the phrase and its reply marker under the exact destination provider instance and generation. This exercises the bounded user/assistant transcript handoff, not transfer of hidden reasoning, tool data or an entire unlimited history.

`--scenario all` retains the original five scenarios unless both `--second-provider` and `--second-provider-instance-id` are explicitly supplied; that opt-in appends `interrupt` and `provider-switch`. During this opt-in interruption run, switching to the requested destination while the turn is active must return `turnActive` before the interrupt. The runner stops on the first failed scenario. Second-provider options are accepted only for `provider-switch` or this opt-in `all`; both providers, requested models, runtime modes and required interruption capability are validated before any chat is created. `--second-model` selects an exact destination catalog ID; omission selects its provider default and never carries the primary provider's model across the switch.

`--timeout` is a total deadline per scenario; each RPC, including every polling snapshot, is independently limited by `--request-timeout` (default 30 seconds). `--model` accepts an exact primary catalog ID; omission explicitly selects the host's provider default. `--runtime-mode` defaults to `approval-required`. A request waiting for human input will time out and fail; the runner does not approve it.

Every mutation has a recorded `requestId`, including intentional retries, conflict probes, and cleanup. The report records the unique `runId`, mutation payloads, passed assertions, observed failures, archived fixture chat IDs, and the probe's sanitized responses, events, snapshots, and turn states. New scenarios retain their relevant before/after evidence snapshots separately so cleanup cannot overwrite the interruption or handoff observation. QA reference phrases are deliberately public fixtures, never credentials. Returned in-memory wire values are never printed directly. `--output` writes the same sanitized JSON with mode `0600`; exit status is zero only when every requested scenario, cleanup and output write succeeds. A partial or unwritable output file does not establish a passing run. Reuse a mutation's recorded ID and exact payload for manual recovery, but use a fresh run ID for a new scenario run.

The runner archives only chats it created for the current scenario, including its delegated child, on success or failure, and verifies `archived`, session `stopped`, terminal turns, no active turn, empty queue and pending requests, and no streaming or in-progress items. Cleanup uses a separate bounded budget of at most two RPCs per known chat, each limited to the smaller of ten seconds and `--request-timeout`. Archive preserves transcripts for review; these snapshot assertions do not independently prove an operating-system provider process was reaped. A cleanup error is reported and makes the run fail; the host and existing workspaces remain running. If creation or delegation times out before returning an identity, recover it manually using the exact recorded request ID and payload. The standard-library scenario tests use a deterministic offline `RuntimeProbe` fixture and cover successful scenarios, false-positive prevention, exact conflict codes, queue races, actual project identity, native MCP server/tool evidence, interruption races and acknowledgements, provider handoff boundaries, per-RPC deadlines, redaction, cleanup state and private output failures. They never contact an Alera profile or provider.

## Mac Direct Agent Chat GUI Flow

`mac_agent_chat_direct_flow.mjs` exports `runMacAgentChatDirectFlow` and the pure `inspectMacAgentChatDirectReply` detector for the current direct-open UI. Inject the caller's public Sky API and private `{capture, write, pause, verifyComposer}` callbacks. Supply an explicit QA `appBundleId`, `entry` (`empty-panel`, `add-tab`, or `existing-chat`), exact `workspaceLabel`, `chatLabel`, QA-prefixed `providerLabel`, `modelLabel`, bounded single-line `prompt`, and an uppercase QA `replyMarker` contained in that prompt. `pickerLabel` names the current composer chip when selection is necessary; `modelSearch` is optional. The flow never launches an app, changes workspaces, injects shortcuts, retries a send, or accepts a provider-selection modal.

Every action requires fresh full AX and screenshot evidence. Provider/model selection must be observed in the composer rather than inferred from an earlier transcript. Immediately before Send, `verifyComposer(state, {prompt, providerLabel, modelLabel})` must inspect the actual screenshot and return `{screenshotVerified: true, exactPrompt: true}`. AX field values alone are insufficient: Flutter can expose an AX value that differs from its visible controller text. When Send lacks a semantic label, `selectSendTarget(state)` must similarly inspect that fresh image and return `{screenshotVerified: true, element_index}` or `{screenshotVerified: true, x, y}`. Do not substitute unconditional callbacks for either visual check.

The optional read-only `confirmRuntime` callback keeps durable completion separate from visible reply evidence. Without it, a stable assistant marker can establish `replyValidated` while `turnTerminalStatusVerified` remains false. Failed and cancelled terminal statuses are reported independently from successful output. Keep screenshots, control metadata and driver logs private; the macro report contains bounded observations and evidence paths. Native replay requires the injected callbacks and a real app; fixture tests do not establish native acceptance.

```sh
node --check tool/qa/mac_agent_chat_direct_flow.mjs
node --test tool/qa/mac_agent_chat_direct_flow_test.mjs
```

The fixtures cover direct-entry and selection guards, stale snapshots, modal rejection, wrong workspace/chat, preserved drafts, truthful focus and screenshot verification, ambiguous Send targets, bounded observation, user-echo false positives, stable assistant replies, independent runtime confirmation and at-most-one send. See [native rendering measurement](agent_chat_performance.md) for the separate provider-free profile benchmark.

## Legacy Modal Agent Chat GUI Flow

`mac_agent_chat_flow.mjs` exports `runMacAgentChatFlow`, a matching default export, and the pure `inspectMacAgentChatReply` detector. It imports no plugin and references no `nodeRepl` global. Import the public Sky API in the caller, then inject `{sky, capture, write, pause, appBundleId, entry, workspaceLabel, providerLabel, prompt, observeSeconds}`. `entry` defaults to `shortcut`; `dialog` is an explicit opt-in for an operator who freshly opens an owned QA New Agent Chat dialog through the visible plus/menu. Dialog mode requires an explicitly supplied QA bundle, an initial screenshot, the exact named dialog and workspace description, and skips workspace selection and shortcut injection. The default shortcut bundle is `dev.leynier.alera.agentqa.20261013`; only `dev.leynier.alera.agentqa` bundles are accepted. The workspace label must start with `QA`. The single-line prompt must contain one uppercase QA marker, such as `GUI-CODEX-QA-20261013`.

```js
const {sky} = await import('@oai/sky');
const fs = await import('node:fs/promises');
const {fileURLToPath, pathToFileURL} = await import('node:url');
const {runMacAgentChatFlow} = await import(pathToFileURL('/path/to/checkout/tool/qa/mac_agent_chat_flow.mjs').href);
const evidenceDir = '/path/to/private/qa-gui-evidence';
await fs.mkdir(evidenceDir, {recursive: true, mode: 0o700});
const result = await runMacAgentChatFlow({
  sky,
  entry: 'shortcut',
  appBundleId: 'dev.leynier.alera.agentqa.20261013',
  workspaceLabel: 'QA Alpha',
  providerLabel: 'QA Codex',
  prompt: 'Reply with GUI-CODEX-QA-20261013 and a short markdown table. Do not read files or execute tools.',
  observeSeconds: 60,
  pause: milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)),
  write: value => nodeRepl.write(value),
  capture: async ({label, sequence, state}) => {
    const stem = `${evidenceDir}/${String(sequence).padStart(2, '0')}-${label}`;
    const axPath = stem + '.ax.txt';
    await fs.writeFile(axPath, state.text, {mode: 0o600});
    let screenshotPath = null;
    if (state.screenshot) {
      screenshotPath = stem + '.png';
      await fs.copyFile(fileURLToPath(state.screenshot.url), screenshotPath);
      await fs.chmod(screenshotPath, 0o600);
    }
    return {axPath, screenshotPath};
  },
});
await fs.writeFile(evidenceDir + '/result.json', JSON.stringify(result, null, 2) + '\n', {mode: 0o600});
```

Each action takes a full fresh AX snapshot before selecting an index and captures the resulting state afterward. An explicit stale-snapshot rejection gets one fresh selection and retry for safe selections. Typing and Return are each attempted at most once and are never retried, including a stale rejection or ambiguous failure. Shortcut mode refuses a pre-existing creation dialog and opens its own with `super+shift+t` (`Mod+Shift+T`), then checks the exact dialog workspace sentence. Hardware Cmd+Shift+T was verified with the composer focused; that does not establish equivalent delivery by a computer-use tool. If injected keys leave no dialog in the fresh snapshot, the flow stops without typing or sending; use explicit dialog mode after the operator's visible menu action rather than inferring an app shortcut defect or guessing tool internals.

Both entry modes select the exact provider label in the actual dropdown and start a new chat. Native startup can hide the empty hint and composer, so the macro waits at most 30 seconds for the selected provider, empty composer and `Send a message to start.` ready hint before focusing or typing. This deadline includes snapshot and capture calls. Visible provider errors or a nonempty composer fail immediately. The flow then types the exact prompt once and sends with Return. It uses no pixel coordinates and closes no app, tab, workspace, or pre-existing dialog.

A background app's full AX snapshot may omit focused-element metadata or identify a generic root. After the explicit composer click, fresh screenshots and exactly two expected text fields are required; an explicitly different editable focus rejects before typing. Absent or generic focus metadata can proceed to one typing attempt, but the exact prompt must appear in the intended composer and the sidebar text must remain unchanged both after typing and before Return. Misdirected or no-op typing fails without sending. The macro does not raise the app or use guessed focus APIs, and missing AX focus metadata alone does not establish an app defect.

After freshly opening New Agent Chat for QA Beta through the visible plus/menu, reuse the caller-owned `sky`, `capture`, `write`, and `pause` helpers. A distinct import URL loads the repaired module in a persistent Node REPL without reusing an earlier cached module; `var` bindings permit repeating the caller cell:

```js
var qaDialogModule = await import(pathToFileURL('/path/to/checkout/tool/qa/mac_agent_chat_flow.mjs').href + '?reply-detector-v3-merged');
var qaBetaResult = await qaDialogModule.runMacAgentChatFlow({
  sky, capture, write, pause,
  entry: 'dialog',
  appBundleId: 'dev.leynier.alera.agentqa.20261013',
  workspaceLabel: 'QA Beta',
  providerLabel: 'QA Codex',
  prompt: 'Reply with GUI-CODEX-QA-20261013-BETA. Do not read files or execute tools.',
  observeSeconds: 60,
});
```

The observation requires the exact marker token in read-only text after the complete persisted user prompt and before the empty composer, with no working indicator. Flutter AX may expose prompt and reply in separate rows or merge them into one row whose exact prompt label has a distinct reply suffix on later lines. The detector strips the entire bounded single-line prompt before examining that suffix. It rejects markers solely in the prompt, composer or sidebar, duplicate or repeated prompts, working indicators and wrong marker variants. The macro still requires the same reply text in two observations. Visible provider errors fail the flow. The report contains the marker and evidence paths rather than raw provider error or assistant text, plus the selected `entry`, `emptyChatReadyObserved`, `composerFocusMetadata` and `typingAttempted`. Attempt flags record calls rather than provider delivery. `replyValidated` proves that UI observation; `turnTerminalStatusVerified` remains false because durable runtime completion belongs to the runtime scenario runner. Review the captured screenshots separately. The flow is limited to five minutes, individual calls to 30 seconds, creation and readiness each to 30 seconds, observation to at most 180 seconds, and final report writing to five seconds.

For an already-completed chat, use `inspectMacAgentChatReply({state, prompt})` on full saved or freshly captured AX snapshots without rerunning the create/type/send flow. The detector never calls Sky, changes the snapshot, or updates an earlier timeout report. It returns `null` when no qualifying reply is observed, otherwise `{marker, text, indices}`; `text` is only the candidate reply and remains caller-owned in memory. Two independent observations with equal nonempty reply text establish the same stability check as the macro. Keep any later observation as separate evidence, preserve the original report, and verify durable completion through the runtime independently:

```js
var qaReplyDetector = await import(pathToFileURL('/path/to/checkout/tool/qa/mac_agent_chat_flow.mjs').href + '?reply-detector-v3-merged');
var firstReply = qaReplyDetector.inspectMacAgentChatReply({state: savedState, prompt: exactRecordedPrompt});
var secondReply = qaReplyDetector.inspectMacAgentChatReply({state: freshState, prompt: exactRecordedPrompt});
var stableReplyObserved = Boolean(firstReply && secondReply && firstReply.text === secondReply.text);
```

```sh
node --check tool/qa/mac_agent_chat_flow.mjs
node --test tool/qa/mac_agent_chat_flow_test.mjs
```

The Node built-in fixtures exercise owned-dialog entry, wrong workspace and bundle rejection, default shortcut safety, no-op injected keys, late or missing native readiness, visible startup errors, preserved drafts, stale selectors, bounded hanging snapshot calls and one-send behavior. They also cover the observed background AX shape with fields 6 and 53 and no focus footer, generic focus, explicit sidebar focus, misdirected/no-op typing and sidebar drift before Return, plus the merged reply row 49 and empty composer row 50, pure snapshot inspection, false marker matches and two-sample stability. They use scripted AX snapshots and a mock clock without loading Sky or driving a native app.

Process inventories must report only process IDs and short names. Runtime startup arguments can contain authentication tokens; do not capture full command lines, environment dumps or control-file contents in reports or artifacts.
