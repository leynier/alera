---
name: alera-mcp-agent-profiles
description: Inspect, create, change, reorder, and remove Alera agent profiles through this MCP server. Use when the user asks to maintain the launch catalog of coding agents.
metadata:
  version: 1
---

# Alera Agent Profiles Through MCP

An agent profile is a launch recipe for a coding agent: an adapter (`agentType`) plus either a command line or a managed configuration. Workspaces, delegation, and automations launch agents by profile.

## Reading

`list_agent_profiles` lists them. `show_agent_profile` shows one with its launch configuration and revision, by id or unique name. Reading is always allowed; launching is in the `alera-mcp` skill.

## Changing

Every change needs administrative access and must be covered by the user's request. Honor a prior explicit request for the same change without asking again; a proposal-only request stops at the proposal.

- `create_agent_profile` creates one. A command profile takes `command`. A managed profile takes `managedConfig` with the keys its adapter supports; read [managed configuration](references/managed.md).
- `update_agent_profile` changes only the given fields. Pass `expectedRevision` from `show_agent_profile` to refuse a stale edit. Changing the adapter of a managed profile needs a new `managedConfig`.
- `reorder_agent_profiles` sets the whole order: list every current profile id exactly once.
- `set_default_agent_profile` chooses the profile New Workspace from Prompt uses when none is named.
- `remove_agent_profile` removes one. Run `preview_agent_profile_removal` first, report what refers to it (such as automations), and remove it only when that is covered by the request.

Re-read the changed profile or the order afterwards to confirm it was saved.

## Reduced Protections

Never infer permission to reduce an agent's protections from a general profile request. Settings that skip permission prompts, bypass sandboxes, or approve actions automatically need the user's explicit intent and `confirmReducedProtections`.

Examples are Codex bypass or never-ask approval, Claude bypass permissions, Copilot allow-all, Cursor force or trusted workspace, and OpenCode auto approval.
