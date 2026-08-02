---
title: "Welcome To Alera"
description: "Why we started building a native workbench for CLI coding agents, and what you can do with it today."
pubDate: 2026-07-28
---

This blog starts with a confession: we built Alera because we could not find the tool we wanted to use ourselves.

Our days already revolved around CLI coding agents. Claude Code in one terminal, Codex in another, something new every other week. The agents kept getting better, but the setup around them stayed stuck: a pile of terminal windows, a few tmux sessions we were afraid to close, and a constant low-grade anxiety about which agent was touching which files.

The new wave of AI IDEs did not solve it for us. They wrap a single chat backend inside an Electron shell and ask you to leave your CLI behind. We did not want to leave the CLI behind. The CLI is where the agents live.

So Alera takes the opposite bet. It is a native, performance-first workbench for CLI coding agents: Claude Code, Codex, Amp, Antigravity, OpenCode, Cursor, Copilot, Pi, or anything else that runs in a terminal. Flutter and Rust under the hood, Ghostty's VTE for terminal parsing. No Electron, no bundled Chromium, no browser pretending to be a terminal.

## What You Can Do Today

- Run several agents in parallel, each in its own workspace and Git worktree, without them stepping on each other
- Close the window without killing your agents; sessions belong to a runtime host, not to the UI
- See which agent is working, which is waiting on you, and which one is eating your CPU
- Use the same workbench on macOS, Windows, and Linux, with a signed package repository on Linux

We wrote up the details in follow-up posts, linked throughout this one. The short version: the boring infrastructure around agents (worktrees, PTYs, quotas, resources) is the part we think deserves real engineering.

## Get Started

Install from the [download page](/download), or run:

```bash
curl -fsSL https://alera.build/install.sh | sh
```

Then open Alera and start an agent the same way you would in any terminal. If something feels off, we want to hear about it: issues and feedback live on [GitHub](https://github.com/leynier/alera), and we read them.

This is a public beta and it is moving fast. We will use this blog to write honestly about what we are building, what broke along the way, and what we changed our minds about. Thanks for being here at the start.
