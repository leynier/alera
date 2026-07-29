---
title: "A Native-First Agent Workbench"
description: "Why we bet on Flutter, Rust, and Ghostty instead of shipping another Electron shell around CLI agents."
pubDate: 2026-07-28
---

Every few months someone asks us why Alera is not an Electron app. It is a fair question. Electron is the path of least resistance for a desktop tool, and if your product is essentially a chat window, the tradeoffs are easy to swallow.

But a workbench for CLI agents is not a chat window. It is a terminal emulator, a process supervisor, and a workspace manager that happen to share a screen. Those are exactly the workloads where a web view shows its seams.

## The Workload Nobody Designs For

Agent sessions are chatty in a way human sessions are not. A single agent can stream output for an hour straight. Multiply that by four or five agents in parallel, add process trees, scrollback, and workspace state, and you have a UI that never gets to idle.

We watched early prototypes spend more CPU redrawing terminal output than the agents spent producing it. That is the moment the architecture stops being a preference and becomes the product.

## The Bet We Made

Alera splits into two processes with a clear contract:

- **Flutter for the UI.** Native rendering on macOS, Windows, and Linux, one codebase, no browser runtime in the frame pipeline.
- **Rust for everything that can hurt you.** PTYs, process trees, scrollback, and resource sampling live in a sidecar that owns the dangerous parts and keeps working even when the UI is not open.

Terminal parsing follows Ghostty's VTE path, which is battle-tested by people who care about terminal correctness far more than most.

We wrote about the streaming side of this story in [why terminal output performance matters](/blog/why-terminal-output-performance-matters-for-agent-workbenches), including the Linux-specific surprises that made us pace frame production instead of just optimizing frames.

## What You Actually Get

None of this matters because it is elegant. It matters because of what falls out of it: agents that survive a closed window, a status bar that can afford to sample CPU per tab, and a workbench that feels like part of your machine instead of a tab you accidentally opened outside the browser.

We are not claiming native is free. Three platforms mean three sets of platform behavior to respect, and some things (Windows console quirks, we are looking at you) cost us real time. We still think the bet was right, and this blog will keep showing our work.

If that trade sounds good to you, [download Alera](/download) and judge the feel for yourself.
