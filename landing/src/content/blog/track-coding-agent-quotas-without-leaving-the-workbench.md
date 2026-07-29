---
title: "Track Coding Agent Quotas Without Leaving The Workbench"
description: "Hitting a provider limit mid-run is the worst way to learn your quota. We put Claude, Codex, Kimi, Grok, Cursor, and more in the status bar."
pubDate: 2026-07-28T16:00:00.000Z
---

There is a specific kind of frustration that only agent users know: a run dies mid-task, you dig through the output, and the cause is a rate limit you did not know you were near. The fix was never technical. You just needed to see the number before it hit zero.

With several agents running in parallel, that visibility stops being optional. Each provider drains a different bucket at a different rate, and the buckets live on websites you do not want to keep open. So we brought them into the workbench: a quota bar at the bottom of the window, next to the terminals you are already watching.

## What You See

Each enabled provider shows its agent icon and its available usage windows. Hovering opens a card with the remaining percentage, a completion bar, and a countdown to reset. Clicking pins the card open; one card at a time, because a status bar is not a dashboard.

Quotas refresh every 15 minutes, can be refreshed by hand, and keep the last successful snapshot marked as stale when a refresh fails. Stale-but-labeled beats blank.

## Who Is Covered

- Claude Code (default account and CCS profiles)
- Codex
- Kimi Code
- Grok Build
- Cursor
- Antigravity
- MiniMax Token Plan
- Z.ai

Provider order is configurable in **Settings → Quotas → Providers**, and Claude CCS profiles can be reordered independently. Show the ones you actually pay for; hide the rest.

## The Part We Designed Most Carefully: Credentials

Quota checks need credentials, and credentials are where a feature like this can go wrong. So the rules are strict.

Alera stores environment variable *names* for API-based plans. Never values. Local desktop and mobile requests go through the runtime-host quota service, and for the local host, missing variables can be resolved from your login shell and held in memory without being persisted into quota responses.

SSH workspaces query through `alera runtime-proxy` on the remote host, so credentials stay on the machine where the agent actually runs. They never travel to your laptop just so a widget can render.

## Claude CCS Profiles

If you run Claude against more than one account, **Settings → Quotas → Claude** handles Default and CCS profiles, each with an alias and a CCS instance directory. Quota lookups set `CLAUDE_CONFIG_DIR` only for the lookup itself; how your terminals launch Claude is untouched.

When a profile is unhealthy and the runtime supports it, the card can offer **Try With TUI**, which scrapes `/usage` for that account only. It is a fallback, not the normal path, and it stays scoped to the profile that needs it.

## Why It Lives In The Workbench

We could have shipped this as a standalone widget or a browser extension. It belongs in the status bar for the same reason [orchestration](/blog/inter-agent-orchestration-in-alera) and live activity do: the decisions quota informs (dispatch another agent now, or wait for the reset?) happen where the agents run.

Enable the providers you use and stop learning about limits from failed runs. [Download Alera](/download) to try it.
