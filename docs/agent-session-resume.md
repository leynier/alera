# Agent Session Resume

The desktop agent profile launch dialog offers **New Session** and **Resume Session**. New sessions accept an initial prompt and attachments, or **Start Without Prompt**. Resume accepts a native conversation ID and opens a new tab using the selected profile. Each deliberate launch creates a separate tab, even when another tab already uses that conversation ID.

The conversation must be accessible to the selected agent and account on the runtime executing the tab. Alera does not transfer conversations between runtimes. Resume does not send an initial prompt, profile custom prompt, or project prompt appendix. Model, effort, permissions and account options stay in the launch configuration where the agent supports them. The explicit ID replaces fx's managed **Resume Last** option. Ambiguous custom shell commands or commands containing conflicting session selectors are rejected before tab creation; use a managed profile or a simple command instead. Custom resume commands require an unquoted executable path without escaped spaces. Shell wrappers, environment assignments and package runners such as `npx` or `bunx` are rejected because resume arguments may not reach the agent. Simple Claude CCS commands remain supported.

The host persists `agentNativeSessionId` and `agentNativeSessionAgent` with the existing immutable `agentProfileLaunchV1` snapshot before starting the PTY. The native conversation ID is distinct from the tab and PTY IDs. Renaming and projected client updates preserve the binding; host recovery resumes it from the saved snapshot without requiring the profile catalog entry. Normal parent-session hooks can confirm or update the active conversation identity, while subagent hooks cannot replace it.

`resumeSessionId` is an optional field on the profile launch requests. Desktop resume requires the additive `agentProfileSessionResumeV1` capability and uses `agentProfile.launchIdempotent` without legacy fallback. The normalized ID participates in receipt conflict detection; requests without it retain the existing digest. Strict protocol versions and storage schemas are unchanged.

Validation and launch errors stay in the dialog. Errors reported by the agent after its process starts appear in the tab's terminal; a successful process launch does not prove the conversation exists. Alera never retries a failed resume as a fresh conversation. Resume controls are disabled on runtimes without the capability.

A plain tab created with a command (`alera tab create --command claude`) is typed by the desktop when its terminal starts. Once its agent reported a resumable conversation, the host answers that terminal's attach with `initialCommandOverride`, the resume form of the same command, and the desktop types that instead. The field is additive: an older desktop types the original command, and an older host sends nothing.

## Restored Settings

Hooks also report the model, effort and permission mode the conversation is running with. The host keeps the latest values on the tab as the host-owned `agentNativeSessionSettings` key (Agent Profile `managedConfig` names, so the profile flag builders render them) and refines them from the agent's own session file at turn boundaries: the last `turn_context` of a Codex rollout, a Grok session's `summary.json`, a Copilot session's `events.jsonl`. A later event refines the stored set; a different conversation id starts a new one. Files are only read for workspaces on this machine.

When a PTY is recreated, the resume line carries those values instead of the ones the tab was first launched with:

| Agent | Reapplied on resume | Dropped from the resumed launch |
|---|---|---|
| Claude | `--permission-mode` (hooks report `default`, which is `manual`), `--effort` | `--model`, because Claude restores the conversation's model unless a flag overrides it |
| Codex | `--model`, `model_reasoning_effort`, `--sandbox`, `--ask-for-approval` | the bypass and `--full-auto` shortcuts when a sandbox or approval value replaces them |
| Grok | `--model`, `--effort`, `--permission-mode` | `--sandbox`, which a resume refuses to change |
| Copilot | `--model`, `--effort`, `--mode` | |
| Antigravity | `--model` | |
| Cursor | | `--model`, restored from the conversation |
| Pi | | `--model` and `--thinking`, restored from the conversation |

A value the profile builder rejects is skipped and the launch keeps its own flag. A Command-mode line keeps any flag the user wrote and only gains the missing ones. Codex plan mode has no launch flag and cannot be restored; OpenCode, Amp and fx keep their own launch.

## Workspace Session Ledger

Every conversation a hook reports is also recorded in the runtime store table `agentNativeSessions`, keyed by workspace, agent and id, with the CCS profile, working directory, tab and last settings. The ledger outlives the tab: a tab record is deleted when it closes or its process exits, and a `/clear` replaces the tab's binding, but the workspace still knows every conversation that ran there. Opening the store seeds the ledger from tabs bound before it existed. A workspace transfer (Hand On) moves the rows with the tabs. Removal paths do not cascade into the ledger, so the host can still read it after the workspace record is gone; rows of workspaces that no longer exist are pruned after each removal.

## Deleting Sessions With A Workspace

The runtime setting `deleteAgentSessionsOnWorkspaceRemoval` (Settings, Application, Safety; off by default) deletes those conversations natively when the user removes a workspace through `workspace.removeManaged` or `workspace.removeShared`. Automation cleanup, run cleanup, record-only removal (`workspace.remove`), project removal and remote (SSH) workspaces are not affected. The plan is captured after the workspace's sessions are stopped and before the removal commits, and runs on its own task after it succeeded, so a slow or failing agent CLI never delays or fails the removal. Conversations the ledger also places in another live workspace are never touched.

- A linked worktree: everything each agent stores for that exact path, plus the recorded conversations.
- The main checkout: only the recorded conversations, since its directory and anything else run there stay.

Each agent uses its own mechanism: `claude purge <path> --yes` per Claude config directory and CCS instance (per-session files for the main checkout), `codex delete --force <id>`, `opencode session delete <id>`, `grok sessions delete <id>`, `amp threads archive <id>` (Amp threads are account-wide cloud objects, so they are archived rather than deleted), and removal of the session files for Cursor, Pi, Copilot, Antigravity and fx. Agent CLIs are resolved through the login shell environment. Running sessions (Copilot and fx locks, Antigravity conversations that are not idle) are skipped. Outcomes are logged without conversation content.

## Automation Recovery

Admitted automation runs have an explicit exception to ordinary session restoration: after owner reconciliation, the runtime attempts the saved native conversation first. If resume fails or is not acknowledged within two heartbeat intervals (at least 120 seconds), it can launch a new conversation with the original task, previous summary/error, and bounded Git status and diff statistics in the preserved workspace. Each attempt has its own terminal and checkpoint. No terminal output or file contents are copied into the retry prompt. The same saved launch configuration and permissions apply, with three total launches by default and the original 24-hour deadline. Watching does not launch or take over; explicit Take Over stops automatic recovery.
