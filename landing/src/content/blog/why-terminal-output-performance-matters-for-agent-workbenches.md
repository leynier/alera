---
title: "Why Terminal Output Performance Matters For Agent Workbenches"
description: "A chatty agent can stream output for an hour straight. That is a frame budget problem, and on Linux it is worse than you think."
pubDate: 2026-07-28T11:00:00.000Z
---

Here is a workload most UI frameworks never have to survive: a process that writes to the terminal continuously, for an hour, while four of its siblings do the same in neighboring panes. That is a normal afternoon for a coding agent workbench, and it breaks the assumptions most desktop apps are built on.

We learned this the hard way on Linux, and the story is worth telling because it changed how we think about frames.

## The Linux Surprise

On Linux, Alera's GTK embedder composites in software. Every frame costs CPU proportional to the window's pixel count, whether or not anything meaningful changed on screen. There is no GDK setting that makes it free.

The consequence is counterintuitive: when output never stops, reducing *how many frames you produce* beats making each frame cheaper. A slightly more efficient frame, produced at full vsync for an hour, still melts the pipeline. Fewer frames is the optimization.

## What Alera Actually Does

- **Paced flushes.** Terminal output flushes have a cadence floor of about 33 ms, so a process writing non-stop cannot drive the frame loop at full vsync. Quiet terminals still flush on the next frame, because typing echo has to feel instant. Streaming bulk output and human input are different workloads and we pace them differently.
- **Host-owned backpressure.** The Rust host batches output and bounds it in bytes. A client that falls behind resynchronizes from a delivery cursor instead of replaying the whole scrollback, which is the difference between a hiccup and a flood.
- **Separate lanes.** RPC and runtime events travel on a control lane, so terminal backpressure can never disconnect the workbench. The moment control traffic shares a lane with bulk output, a chatty agent becomes a denial-of-service attack on your own UI.
- **Sampling off the UI.** [Resource Manager](/blog/see-which-agent-is-eating-your-cpu) sweeps stay in the sidecar. Process table scans have no business on the isolate that renders frames.

The broader split stays as designed: Flutter renders, Rust owns PTYs and processes, parsing follows Ghostty's VTE path. No Electron, no Chromium event loop anywhere in that hot path.

## Measure First, Claim Second

Our rule for performance work is that it starts from a reproducible profile, not from vibes. The repo carries the harnesses (`make perf-linux`, `make app-profile`, resource benchmarks) and we change one bounded subsystem at a time so regressions have somewhere to hide.

It also disciplines what we say publicly. You will not see us claim "fastest IDE." You will see claims like "fewer wasted frames under sustained stream," because that is what we can measure. We would rather be boringly right than loudly wrong.

## The Other Half Of Native

This post is the operational sibling of [native-first](/blog/native-first-agent-workbench). The architecture only pays off if streaming agents do not melt the frame pipeline, and getting that right is ongoing work, not a launch checkbox.

If you want to see it under stress: [download Alera](/download), point your chattiest agent at a big repo, and watch the Resource Manager while it streams. That is the scenario we optimize for.
