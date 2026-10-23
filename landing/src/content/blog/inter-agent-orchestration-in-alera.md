---
title: "Inter-Agent Orchestration In Alera"
description: "Tabs full of agents are useful until they need to coordinate. How orchestration protocol v2 adds ownership, gates, and a real coordinator."
pubDate: 2026-07-28T17:00:00.000Z
updatedDate: 2026-10-23
tags: ["Orchestration", "Agents"]
relatedDocs: ["orchestration", "runs", "agent-profiles"]
---

> **Update, October 2026:** Alera now speaks orchestration protocol v3, and several commands below changed.
>
> - Workers no longer accept dispatches or send heartbeats. The first worker command (`context`, `ask`, `escalate`, or `complete`) accepts the task, terminal activity keeps it alive, and `complete` needs only `--summary`. `dispatch-accept`, `heartbeat`, and `worker-done` are gone.
> - `delegate` replaces `task-create` and `agent-spawn`, and always starts a catalog profile. The minimal loop below is corrected.
> - Execution policies became plans: `run new --approval` holds a run behind a plan gate you resolve, and the `run-policy-*` commands are gone. Runs, gates, and questions live in **Activity** (`Mod+Shift+A`), which replaces the Run Board. See [Runs And Activity](/docs/runs).
> - OpenCode v1 and OpenCode 2 are one agent again, `opencode`: both install as `opencode`, and Alera detects which one you have and launches it accordingly. Profiles and settings that still say `opencode2` keep working as `opencode`.
>
> **Update, September 2026:**
>
> - The adapter registry now also includes `opencode2` (OpenCode 2) and `fx`.
> - A profile now has a launch mode: **Command**, where you write the launch line, or **Managed**, where you pick options such as model and permissions and Alera builds the launch. A profile can also carry a custom prompt.
> - `--json` goes before the subcommand, so the listing command is `alera orchestration --json agent-profiles`. The example below is corrected.
> - You can also manage profiles with the `alera agent-profile` CLI, and an agent with the optional Agent Profiles Skill can create or edit them when you ask it to. The coordinator's own `orchestration agent-profiles` view stays read-only.
> - The built-in coordinator loop launches only catalog profiles or adapter defaults, but `alera orchestration agent-spawn` still accepts an explicit `--command` from the coordinator that owns the task. Spawning with `--profile` is what keeps a worker inside the catalog.

Running five agents in parallel is a superpower right up until they need to work *together*. Who owns this task? Did that worker finish or crash? Which agent is allowed to approve the risky step? "A bunch of terminals" has no answers to those questions, and we learned that by watching our own multi-agent sessions dissolve into guesswork.

Orchestration is our answer, and it lives where it has to: in the Rust runtime host, as orchestration protocol v2, not bolted onto the UI.

## What Ships Today

- **Workspace-scoped coordinator runs.** A workspace has at most one active run. Unrelated workspaces can coordinate concurrently without knowing about each other.
- **Durable task ownership.** Tasks and dispatches persist in the runtime SQLite database, so a restart does not vaporize who was doing what.
- **Atomic spawn, readiness, and acceptance.** Workers start through registered adapters and explicitly accept dispatches. No half-launched ghosts.
- **Decision gates and messaging.** Blocking decisions and persistent messages between agents, for the moments that need a judgment call.
- **Agent profiles.** User-declared launch configurations the coordinator may dispatch to. More on these below, because they embody the design philosophy.

One rule sits under all of it: mutations pass through the authenticated host actor. Authority comes from the run or task coordinator, not from whichever terminal happened to call a command. It sounds abstract until an agent tries to promote its own work; then it sounds obvious.

## Agent Profiles: The Catalog Is Yours

Profiles live in Settings → Agent Profiles. Each one has a name, an adapter from the built-in registry (`codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `pi`, `amp`, `grok`, and related defaults), an interactive launch command, a description that acts as a routing signal, and an optional quota group.

The CLI can list them:

```bash
alera orchestration --json agent-profiles
```

Here is the part we care about: only you create or edit profiles. A coordinator picks from that closed catalog; it never invents a launch command. The moment a coordinator can compose its own commands, your approval flow is theater. We chose the boring, auditable option on purpose.

## A Minimal Loop

```bash
alera orchestration --json delegate --profile "Codex Sol" --spec "Review tests"
alera orchestration --json run new --profile "Codex Sol" --spec "Audit the repository" --isolation shared
alera orchestration --json run list --workspace <workspace-id>
alera orchestration --json run show --run <run-id>
```

Workers accept, heartbeat, escalate, and complete through the orchestration CLI, with context inferred from the active terminal. Completion validates structured results and promotes dependent work in a single response, so a finished task can unblock the next one without a human relay.

## Execution Policies, Opt-In

A run may carry a stage plan that you approve before dispatch: a preferred profile per stage, plus ordered fallbacks. Scheduling holds until you approve or reject the plan. Runs without a policy behave exactly as before, because coordination you did not ask for should never change how your workspace behaves.

## The Honest Scope

Orchestration is for durable multi-agent coordination inside Alera-managed workspaces. It does not replace your agent CLIs; it schedules and owns the work they accept. The full contract lives in the repo docs, and we expect it to keep evolving as we run more of our own work through it.

When one agent stops being enough, you will know. That is the moment to [open a coordinator run](/download).
