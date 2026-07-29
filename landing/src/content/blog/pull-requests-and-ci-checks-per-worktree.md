---
title: "Pull Requests And CI Checks Per Worktree"
description: "Review belongs next to the work. How the Pull Requests panel keeps GitHub, GitLab, and Azure DevOps scoped to the worktree that produced the branch."
pubDate: 2026-07-28T12:00:00.000Z
---

Parallel agents produce parallel branches. That is the point of the whole worktree model. But it creates a review problem nobody talks about: when three agents ship three branches at once, where do you actually review them?

Our first answer was "in the browser, like everyone else." It did not last. Hopping between the workbench and a forge tab for every PR broke the exact flow we built the worktrees for, and worse, it detached review from context. You would look at a diff and have to reconstruct which agent, which task, which workspace produced it.

So the Pull Requests panel in Alera operates per worktree. Open it from a linked workspace and you are looking at the branch that workspace owns. The review surface matches the agent that did the work, by construction.

## What You Can Do Without Leaving

- Create, edit, comment (with Markdown), toggle draft, and merge
- Inspect CI checks grouped by status, with drill-down into the details when something goes red
- Generate PR titles and descriptions from the branch's changes with AI assistance, which is handy when the agent was terse
- Jump to the repository in your browser from the workspace menu, for the moments you genuinely want the forge UI

## GitHub, GitLab, And Azure DevOps

We did not build forge clients from scratch. Alera speaks to the official CLIs you already authenticate with:

- GitHub and GitHub Enterprise Server, via `gh`
- GitLab, including self-managed, via `glab` (review pagination needs `glab` 1.80.0 or newer)
- Azure DevOps, via `az`

Self-hosted GitHub and GitLab instances are selected explicitly in project settings or in [`alera.toml`](/blog/automate-new-worktree-setup-with-alera-toml). Alera reads the hostname from the repository remote and hands it to the right CLI. Authentication is `gh auth login`, `glab auth login`, or `az login`, with hostname flags for enterprise hosts. One honest caveat: our landing page's feature summary highlights GitHub and Azure DevOps, but GitLab works the same way through `glab`, as described above.

## Why Per Worktree, Again

It comes back to [worktree isolation](/blog/run-cli-agents-in-parallel-with-git-worktrees). Reviewing from a shared primary checkout mixes diffs and check results across tasks. Scoping the panel to the linked workspace means the branch you merge is the branch the agent touched, the checks you see belong to that branch, and nothing bleeds across contexts.

If your forge CLI is already authenticated, you are one workspace away from trying this. [Download Alera](/download) and open Pull Requests from the worktree that owns the branch.
