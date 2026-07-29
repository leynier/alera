---
title: "Run CLI Agents In Parallel With Git Worktrees"
description: "Two agents sharing one working tree is a stash fight waiting to happen. Here is the model we use instead."
pubDate: 2026-07-28T20:00:00.000Z
---

The first time we ran two coding agents against the same checkout, they lasted about ten minutes before trampling each other. One was refactoring a module, the other was adding tests for it, and suddenly we were staring at a working tree full of half-related changes, doing git stash gymnastics to figure out what belonged to whom.

That experience is why parallelism in Alera is not "open more tabs." It is built on a boring, solid Git primitive: the worktree.

## The Model: Project, Workspace, Worktree

Three words carry the whole design, so it is worth being precise.

A **project** is a folder you register in Alera. An existing local path, or a clone from a URL.

A **workspace** is your working context inside that project. The primary workspace points at the project path itself. Linked workspaces, available for Git-backed projects, each point at a separate checkout.

A **worktree** is the Git mechanism behind a linked workspace. When you create one, Alera makes a new local branch from a source branch, or attaches the workspace to a branch you already have. Non-Git folders are not second-class citizens; they just get a single primary workspace, because there is nothing to link.

## Why Isolation Changes The Experience

With one worktree per task, the failure mode from our opening story mostly disappears:

- Each agent sees a clean branch with only its own changes in it
- Diffs stay scoped, so reviewing agent A's work never includes agent B's debris
- You can jump between contexts without tearing anything down, stashing, or remembering what was half-done

There is a subtle benefit we did not fully anticipate: it changes how you delegate. When handing a task to an agent costs one worktree instead of a negotiation with your current branch, you start handing off smaller, better-defined tasks. The tooling nudges you toward the workflow that works.

## From Repo To Running Agents

The loop itself is three steps:

1. Register a project (local folder or clone)
2. Open a linked worktree workspace for each task you want in flight
3. Launch Claude, Codex, Amp, or any other CLI agent in that workspace's terminals

The one annoyance left in this loop used to be setup: every new worktree needs its `.env`, its dependencies, its bootstrap commands. We automated that ritual with [`alera.toml`](/blog/automate-new-worktree-setup-with-alera-toml), and when the work is done, [pull requests and CI checks stay scoped to the same worktree](/blog/pull-requests-and-ci-checks-per-worktree) so what you review is exactly what the agent produced.

If you have been running agents sequentially because parallel felt dangerous, this is the post we wrote for you. [Download Alera](/download), open a Git-backed project, and give your next task its own worktree.
