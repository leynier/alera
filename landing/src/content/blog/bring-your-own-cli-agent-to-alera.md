---
title: "Bring Your Own CLI Agent To Alera"
description: "We did not want to invent another agent protocol. If it runs in a terminal, it runs in Alera - and the big ones get first-class treatment."
pubDate: 2026-07-28T15:00:00.000Z
---

Every few weeks a new coding agent CLI appears, and every few weeks someone asks whether Alera supports it. Our answer has become a reflex: does it run in a terminal? Then yes.

That is not a dodge. It is the design. We never wanted Alera to be a product you adopt by abandoning your tools, and we definitely did not want to invent yet another agent protocol for the world to standardize on. The terminal is already the universal interface. We just give it a better home.

## First-Class Today

Some agents get more than a PTY. These ship with icons, managed lifecycle integrations, and live activity tracking in the workbench:

- Claude Code
- Codex
- Amp
- Antigravity
- OpenCode
- Cursor
- Copilot
- Pi
- Grok Build
- fx

These integrations stream status into Alera, which is what lets the sidebar and activity surfaces tell you who is working and who is quietly waiting for your input. When you run a handful of agents at once, that glanceable state is the difference between conducting and guessing.

## Everything Else

Any other CLI gets the full workbench around it as a normal terminal process: worktree isolation, persistent sessions, quotas, resource tracking, the works. Launch it in a workspace tab exactly the way you would in any shell. Gemini CLI, Goose, Aider, your own in-house script that nobody else has heard of: if your terminal can run it, so can we.

We like this rule because it ages well. The agent landscape reshuffles monthly. A workbench that only supports a fixed list is a workbench with an expiration date.

## Orchestration Adapters

If you go further and coordinate agents through [orchestration](/blog/inter-agent-orchestration-in-alera), agent profiles bind to a built-in adapter registry (`codex`, `claude`, `copilot`, `cursor`, `agy`, `opencode`, `pi`, `amp`, `grok`, `fx`, and related defaults). Profiles are your configuration: you approve the launch command, the coordinator dispatches to it, and nobody invents commands on your behalf.

## Tips From Our Own Setup

- Give each long-running agent task its own [linked worktree workspace](/blog/run-cli-agents-in-parallel-with-git-worktrees). Parallel agents sharing one checkout end in stash fights.
- If GUI-launched terminals cannot see Homebrew or similar prefixes, check the login-shell PATH settings. This one bites macOS users most.
- Keep provider [quotas](/blog/track-coding-agent-quotas-without-leaving-the-workbench) visible while several CLIs run. Parallel agents drain buckets faster than intuition suggests.

Bring the CLI you already trust. [Download Alera](/download) and it will be running in a native PTY within the minute.
