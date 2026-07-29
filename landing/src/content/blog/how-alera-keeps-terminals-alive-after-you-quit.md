---
title: "How Alera Keeps Terminals Alive After You Quit"
description: "Closing a window should never kill a three-hour agent run. The trick is who owns the PTY, and it is not the UI."
pubDate: 2026-07-28T18:00:00.000Z
---

Everyone who runs CLI agents has the scar. You close a window out of habit, or the app updates itself, or you reboot for an unrelated reason, and a run that had been going for two hours is just gone. The agent was mid-refactor. The scrollback with its reasoning is gone too.

We decided early that in Alera, this class of accident simply should not exist. The way we got there is a process boundary: your terminal sessions belong to a Rust runtime host, not to the Flutter window you look at.

## The Split That Makes It Work

The desktop app is the workbench: layout, tabs, interaction. The actual sessions live in a sidecar, the `alera` CLI running as `alera runtime-host`, which owns the things that must survive:

- PTY processes and their whole shell trees
- Bounded scrollback and checkpoints
- Reattach by `terminalSessionId` when a client comes back

Closing the app detaches from those PTYs instead of tearing them down. Reopen Alera and your tabs, layouts, and running processes are where you left them. The window is a viewer. The host is the thing doing the work.

## What Actually Survives

- Terminal tabs and their session ids
- Whatever scrollback the host still retains
- Processes you launched inside those PTYs (within the host lifecycle limits below)
- Workbench layouts tied to the workspace

Lifecycle hooks for the major CLI agents keep streaming state into the host while you are gone, so when you return you can immediately see who finished, who is still working, and who is blocked waiting for you.

## The Host Has A Lifecycle Too

Persistence does not mean a zombie process that never dies. Desktop-started hosts stay alive while they are useful: when clients disconnect and no PTYs are running, the host stops after an empty-host delay. When PTYs are still running, detached sessions stay up for a detached-session delay (one hour by default) before the host checkpoints and exits.

All of this is yours to tune. **Settings → Application → Runtime** controls the empty-host shutdown, the detached-session shutdown, and **Keep Runtime Open When App Quits**. The status bar **Runtime** chip shows whether the host is up and exposes Start / Stop / Update Runtime.

And if you want real permanence, run the host somewhere that is not your laptop: `alera runtime start` on a workstation or VPS, `alera runtime status` to inspect it, `alera runtime stop` when you are done. Pair that with the [mobile companion](/blog/pair-a-phone-to-your-alera-runtime) and you can check on a long run from your phone while your laptop lid is closed.

## Why We Care This Much

Agent runs are long, stateful, and expensive to lose. Treating "the user closed the window" as a reason to kill them is a category error inherited from apps where the window *is* the program. Once the host owns the sessions, a whole family of features becomes easy: reattach, mobile access, remote hosts. That is why the boundary sits at the core of the product instead of in a settings footnote.

Next time you have a run you cannot afford to lose, [leave it with the host](/download) instead of with a window.
