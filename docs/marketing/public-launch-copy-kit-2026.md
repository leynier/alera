# Alera Public Launch Copy Kit

## Founder Launch Thread

Post 1:

> Running one coding agent is easy. Running four turns you into a full-time traffic controller.
>
> I built Alera to coordinate CLI coding agents in parallel without losing control.
>
> Free, open source, and native on macOS, Windows, and Linux.
>
> [demo]

Post 2:

> Every task gets its own Git worktree, terminals, branch, and agent context. Codex, Claude Code, Cursor, Amp, OpenCode, or anything else that runs in a terminal.

Post 3:

> The important part is not opening more terminals. It is knowing who owns each task, who is working, who needs a decision, and what result came back.

Post 4:

> Alera keeps that state durable: task dispatch, agent status, decision gates, structured results, persistent sessions, pull requests, and checks in one workbench.

Post 5:

> I am launching it as a public beta because I want feedback from people already pushing multi-agent workflows past the comfortable limit.
>
> GitHub: https://github.com/leynier/alera
> Download: https://alera.build/download

## Brand Launch Post

> Four agents. One repo. Full control.
>
> Alera gives every CLI coding agent its own Git worktree and coordinates tasks, decisions, and results in one native workbench.
>
> Free and open source on macOS, Windows, and Linux.
>
> https://github.com/leynier/alera

## Show HN Title

> Show HN: Alera - coordinate CLI coding agents across isolated Git worktrees

## Show HN Opening Comment

> I built Alera after my coding workflow became a pile of terminal windows, worktrees, and agent sessions that I was afraid to close. The agents were capable, but I had become the coordination layer.
>
> Alera is a native, open-source workbench that keeps each CLI agent in its own Git worktree and makes task ownership, live status, decisions, and structured results visible in one place. It works with the agents already installed on your machine rather than replacing them with another model or chat backend.
>
> The core workflow is available now on macOS, Windows, and Linux. I would especially value feedback from people already running several agents at once: where does your coordination workflow break first?

## Product Hunt

Tagline:

> Run CLI Coding Agents In Parallel Without Losing Control

Description:

> Alera is a free, open-source native workbench for coordinating CLI coding agents across isolated Git worktrees, persistent terminals, tasks, decisions, and results. Available on macOS, Windows, and Linux.

First comment:

> I built Alera because the difficult part of using several coding agents was no longer prompting them. It was keeping their branches, terminals, status, decisions, and results coherent. Alera keeps the agents you already use and adds the coordination layer around them. I would love to learn where your own multi-agent workflow becomes difficult to manage.

## Targeted Feedback Message

> Hi [name]. I have seen that you use [agents or workflow] in parallel. I am building an open-source workbench called Alera that gives each CLI agent an isolated Git worktree and coordinates their tasks, status, decisions, and results. I am not asking you to promote it. Would you be willing to watch a 60-second silent demo and tell me the first thing that feels unclear or unconvincing?

## LinkedIn Founder Post

> Most people still associate Flutter with mobile apps.
>
> I used it to build a native development environment for coordinating AI coding agents on macOS, Windows, and Linux.
>
> Alera's interface is Flutter. Rust owns the PTYs, persistent processes, Git operations, and runtime state. Ghostty's VTE parses the terminal output. Each agent works inside an isolated Git worktree.
>
> The interesting part was not making the UI look like a terminal. It was keeping Flutter responsive while real agents streamed output, processes survived the window, and platform behavior remained correct across three desktops.
>
> Alera is now free and open source. I am especially interested in feedback from Flutter desktop and performance engineers: which part of this architecture would you inspect first?
>
> [architecture document or native video]

## LinkedIn Alera Page Post

> Alera is a native, open-source agentic development environment built with Flutter, Rust, and Ghostty.
>
> Flutter provides one cross-platform workbench for macOS, Windows, and Linux. Rust owns the process, PTY, Git, and persistent runtime boundaries. Ghostty VTE handles terminal parsing.
>
> This architecture lets developers coordinate CLI coding agents across isolated Git worktrees without replacing the agents they already use.
>
> Explore the architecture and help us test the hard parts of Flutter desktop.
>
> https://github.com/leynier/alera

## LinkedIn Architecture Document

Page 1:

> We Built An Agentic Development Environment With Flutter

Page 2:

> One UI Across macOS, Windows, And Linux

Page 3:

> Rust Owns Processes, PTYs, Git, And Persistent Runtime State

Page 4:

> Ghostty VTE Parses Real Terminal Output

Page 5:

> Every Agent Gets An Isolated Git Worktree

Page 6:

> Flutter Keeps The Human Control Surface Coherent

Page 7:

> Free, MIT-Licensed, And Built In The Open

Page 8:

> Help Us Test The Hard Parts Of Flutter Desktop

## Flutter Forum Post

Title:

> Alera: A Native Multi-Agent Development Environment Built With Flutter And Rust

Body:

> I am the maintainer of Alera, an open-source desktop workbench for coordinating CLI coding agents across isolated Git worktrees.
>
> The desktop UI and design system are implemented in Flutter for macOS, Windows, and Linux. Rust owns PTYs, persistent child processes, Git operations, and runtime state through flutter_rust_bridge, while Ghostty's VTE handles terminal parsing.
>
> Building it has forced us to work through Flutter desktop concerns that do not appear in a typical mobile app: high-volume terminal output, Linux frame pacing, Windows process and keyboard behavior, native menus, persistent sidecars, packaging, and cross-platform performance measurement.
>
> The repository is available at https://github.com/leynier/alera. I would value technical feedback more than promotion. If you were reviewing this as a Flutter desktop application, which architectural or performance area would you inspect first?

## Flutter Slack Or Discord Moderator Request

> Hi. I maintain Alera, an open-source desktop development environment built with Flutter, Rust, and Ghostty. I have written a technical case study about Flutter desktop performance, PTYs, persistent processes, and flutter_rust_bridge. I would like to ask the community for architecture feedback, not advertise a paid product. Which channel, if any, would be appropriate for sharing it? I will follow the workspace rules and keep it to one informative post.

## Approved Flutter Community Post

> I maintain Alera, an open-source agentic development environment whose desktop UI runs on Flutter across macOS, Windows, and Linux.
>
> I documented why Rust owns the PTYs and persistent processes, how Ghostty VTE feeds the terminal surface, and what we learned about Flutter frame production under streaming output.
>
> I would appreciate feedback on [one specific technical area]. The article and source are here: [link]. I am happy to answer implementation questions in this thread.

## Flutter Community AI Circle Proposal

Title:

> Building A Multi-Agent Coding Workbench With Flutter, Rust, And Ghostty

Abstract:

> Alera is a native, open-source environment for coordinating Codex, Claude Code, Cursor, and other CLI coding agents across isolated Git worktrees. Its Flutter interface runs on macOS, Windows, and Linux, while a Rust runtime owns PTYs, persistent processes, Git operations, and durable orchestration state. This session will demonstrate the real product, explain the Flutter and Rust boundary, show what high-volume terminal streaming taught us about desktop performance, and discuss how Flutter can serve as the human control surface for agentic development. The session will include architecture diagrams, measured tradeoffs, source links, and the failures that shaped the design.

Format:

> 25-minute technical walkthrough and live demonstration, followed by open Q&A.
