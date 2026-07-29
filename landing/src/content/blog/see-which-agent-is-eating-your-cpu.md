---
title: "See Which Agent Is Eating Your CPU"
description: "Five agents in parallel and the fans spin up. The Resource Manager names the culprit per tab - including the time it blamed us, 26 times over."
pubDate: 2026-07-28T14:00:00.000Z
---

The moment you run several coding agents at once, your machine turns into a mystery. The fans spin up, everything feels slightly sticky, and the question is always the same: which one of them is doing this?

Answering that with `top` or Activity Monitor means mapping process trees to agent sessions by hand, every time. We wanted the answer in one click, labeled in the vocabulary you already think in. So the Resource Manager attributes live CPU and memory to **Project → Workspace → Terminal tab**, straight from the Rust runtime host that owns those sessions anyway.

## What The Panel Shows

A status-bar chip opens the panel. Per row you get live CPU and memory with sparklines, plus Alera's own app and sidecar rows so we cannot hide our own cost, plus machine-wide memory and load for context.

Our favorite row type is the orphan: a terminal session the host still holds but no tab claims anymore. Those show up labeled as orphans and can be killed in one click. In a workbench with [persistent terminals](/blog/how-alera-keeps-terminals-alive-after-you-quit), orphans are how you catch the agent that outlived its tab.

## The Bug That Taught Us Humility

Here is the part we would rather not admit, except it is too good a story to skip.

While building the sampler, our Linux build started reporting that the Alera app was using 26 times its real memory. Twenty-six. The cause: on Linux, every thread shows up in the process table as a child entry that reports the whole process's RSS. Our app had 97 threads at the time, the sampler dutifully summed all of them, and CPU got double-counted too because the leader's stats already aggregate the thread group.

Nothing in our tree arithmetic could catch it, because every thread id looked like a legitimately distinct process. What caught it was a plausibility check we had almost not written: attributed memory should fit inside the machine's physical memory. It did not, by a factor of 26.

The fix is one flag (skip task entries when refreshing the process table), but the lesson shaped the feature: any number the panel shows must be defensible, or the panel is worse than useless.

## Sampling That Stays Out Of The Way

Two more design rules fell out of that mindset.

Sampling runs in the Rust sidecar, never on the Flutter UI isolate, and only while something is watching. An idle workbench pays nothing for the feature.

And CPU is normalized as a share of the machine, per-core samples divided by core count, so the CPU column reads on the same scale as the memory column. When the core count is unknown, the panel shows nothing rather than a number it cannot stand behind. After the 26x incident, we are sentimental about that rule.

## Why It Matters With Parallel Agents

A stuck install, a runaway build, an agent that forked more children than expected: all of these are trivial to spot when the cost is labeled by workspace and tab, and nearly invisible when it is an anonymous process tree. Parallel agents are only comfortable if you can afford to not think about the machine. This panel is how we get there.

Run a few agents and [open the Resource Manager](/download) while they work. The sparklines tell stories.
