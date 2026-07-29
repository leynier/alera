---
title: "Inter-Agent Orchestration In Alera"
description: "Tabs full of agents are useful until they need to coordinate. How orchestration protocol v2 adds ownership, gates, and a real coordinator."
pubDate: 2026-07-28T17:00:00.000Z
---

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

Profiles live in Settings → Agent Profiles. Each one has a name, an adapter from the built-in registry (`codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `pi`, `amp`, and related defaults), an interactive launch command, a description that acts as a routing signal, and an optional quota group.

The CLI can list them:

```bash
alera orchestration agent-profiles --json
```

Here is the part we care about: only you create or edit profiles. A coordinator picks from that closed catalog; it never invents a launch command. The moment a coordinator can compose its own commands, your approval flow is theater. We chose the boring, auditable option on purpose.

## A Minimal Loop

```bash
alera orchestration task-create --workspace <workspace-id> --spec "Review tests"
alera orchestration run --workspace <workspace-id> --agent codex --spec "Audit the repository"
alera orchestration run-list --workspace <workspace-id>
alera orchestration run-show --id <run-id>
```

Workers accept, heartbeat, escalate, and complete through the orchestration CLI, with context inferred from the active terminal. Completion validates structured results and promotes dependent work in a single response, so a finished task can unblock the next one without a human relay.

## Execution Policies, Opt-In

A run may carry a stage plan that you approve before dispatch: a preferred profile per stage, plus ordered fallbacks. Scheduling holds until you approve or reject the plan. Runs without a policy behave exactly as before, because coordination you did not ask for should never change how your workspace behaves.

## The Honest Scope

Orchestration is for durable multi-agent coordination inside Alera-managed workspaces. It does not replace your agent CLIs; it schedules and owns the work they accept. The full contract lives in the repo docs, and we expect it to keep evolving as we run more of our own work through it.

When one agent stops being enough, you will know. That is the moment to [open a coordinator run](/download).
