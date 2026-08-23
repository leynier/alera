---
title: "Why Alera Is Terminal-First (Not Another AI IDE)"
description: "The case for building around the CLIs you already use instead of wrapping one provider's chat in an Electron shell."
pubDate: 2026-07-28T19:00:00.000Z
---

Here is an opinion we hold strongly enough to build a product on: the CLI is the real interface for coding agents, and it will stay that way for a while.

Every agent team that matters ships a terminal client first. Claude Code, Codex, Amp, Cursor Agent, Copilot CLI, OpenCode, Pi, fx. The terminal is where new capabilities show up earliest, where power users already live, and where the agents compose with the rest of your tools. So when we see an AI IDE embed one provider's chat in a web view and call it the future, our reaction is: that is a wrapper, not a workbench.

## What A Single Chat Shell Costs You

One embedded chat is comfortable if you use one assistant for one thing at a time. The friction starts the moment you want more:

- Several agents on different tasks at once, without them sharing one transcript
- The exact CLI you already configured, with your flags, your aliases, your muscle memory
- A workbench that does not put a browser runtime between you and a process that streams for hours

Wrapping a terminal tool in a web view adds weight and removes control. You inherit someone else's idea of the loop instead of keeping your own.

## What Terminal-First Means In Practice

In Alera, the terminal is not a fallback. It is the point.

- **Any CLI agent runs.** If it works in a terminal, it works in Alera. Open a tab, launch it like you always do.
- **Parallel is the default.** Agents get native PTYs across workspaces and split panes. They are processes, not tabs competing inside one chat history.
- **No Electron, no Chromium.** Flutter renders the UI, Rust owns processes and PTYs, Ghostty's VTE parses terminal output.

Agents we integrate first-class get icons, lifecycle hooks, and live activity tracking on top of that. Everything else still works as a plain terminal process, which is the whole idea: first-class is a bonus, not a gate.

## We Will Say The Quiet Part Too

AI IDEs are not a mistake. If you want one vendor's opinionated chat experience next to a full LSP editor in the same window, they are genuinely good at that, and we are not trying to replace your editor.

Alera is for a different moment: the agent is already a CLI you trust, the repo needs worktree isolation, and you want three of them running at once without negotiating with a single chat box. If that moment sounds familiar, we built this for you.

The natural next read is how [worktrees keep parallel agents from colliding](/blog/run-cli-agents-in-parallel-with-git-worktrees). Or skip the reading and [bring the CLI you already use](/download).
