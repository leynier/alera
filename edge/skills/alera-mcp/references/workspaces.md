# Projects And Workspaces

## Projects

A project is a repository or folder registered in a runtime. `list_projects` shows each project with the hosts it is on.

- Add a folder that already exists with `register_project`. The folder is not changed.
- Clone a repository with `clone_project`. It returns a clone job at once; follow it with `get_project_clone`. `list_project_clones` lists jobs, and `cancel_project_clone` stops one and deletes its partial folder.
- A project can live on SSH hosts too. `list_ssh_targets` lists the hosts the runtime knows, and `ssh_target_status` checks whether they are reachable. `register_remote_project` adds a project that exists only on a host. For an existing project, `add_project_host` adds a host, either from a folder there or by cloning, and `register_project_checkout` registers a specific folder. `list_project_hosts` shows the folder on each host, and `remove_project_host` forgets one without deleting files.
- `list_project_branches` lists the branches that can be a new worktree's `sourceBranch`, and the project's preferred one.
- `get_project_config` shows the effective project settings and whether they come from the app or from the repository's `alera.toml`. `update_project_config` saves app settings that override the file, part by part, and `reset_project_config` goes back to the file or the defaults.
- `rename_project` changes only the display name. `remove_project` removes the project from Alera as the app does: dependent automations are paused, and no file is deleted. Run `preview_project_removal` first and report what it shows.

## Workspaces

`list_workspaces` lists the workspaces of one project or all of them, with filters. `show_workspace` shows one with its section, tags, linked issue, linked pull request, Watch and Fix state, parent, children, and whether it is asleep.

There are four ways to create one:

1. `start_workspace_from_prompt` does what the app's New Workspace from Prompt form does. AI Assist picks the project when `projectId` is left out, names the workspace and branch, picks a section, and launches the agent. When the project is unclear it ends with status `needsInput` and candidates; call again with `projectId`. It answers within about 40 seconds; while the status is `running`, follow it with `wait_for_workspace_start` or `get_workspace_start`. `list_workspace_starts` lists recent operations. `cancel_workspace_start` stops one, and a workspace it already created is kept. If the workspace exists but the agent did not start, `retry_workspace_start_launch` launches it again without creating another workspace.
2. `start_agent_workspace` creates a workspace and launches a named profile with a prompt. A new worktree from `projectId` needs `sourceBranch`.
3. `create_workspace` creates a workspace without starting an agent, as the manual New Workspace form does.
4. `delegate_task` with a new workspace, described in the `alera-mcp-orchestration` skill.

A workspace on its own worktree has its own branch. A workspace on the project folder shares the folder and its branch with every other task there.

## Workspace Lifecycle

- `rename_workspace` changes only the display name; the branch and folder stay.
- `set_workspace_pinned` pins or unpins it in the sidebar. `focus_workspace` selects it in the running desktop app; it fails when no desktop app is connected.
- `sleep_workspace` stops its terminals and keeps tabs, branch, and files. `wake_workspace` starts them again and resumes the agents' conversations.
- `archive_workspace` also hides it from the sidebar; `unarchive_workspace` brings it back.
- `remove_workspace` follows the app's Remove flow. Its sessions close, automations that depend on it are paused, editors open on it are saved, and its worktree is deleted. Uncommitted changes in the worktree are lost. The branch is deleted only when Alera created it, unless `branch` is `keep`. Always run `preview_workspace_removal` first and report the storage, blockers, automations, links, and branch outcome. A `blocked` answer removed nothing.

## Moving Between Folder And Worktree

- `hand_off_workspace` moves a task from the project folder to its own worktree on a new or existing branch, choosing whether uncommitted changes move with it.
- `hand_on_workspace` brings a task from its worktree back to the project folder.
- A relocation runs the project's setup. `get_workspace_recovery` shows its phases and setup attempts. `run_workspace_setup` runs the setup in a workspace. `cancel_workspace_setup` stops a running attempt, and `recover_workspace_setup` closes an interrupted one without running its commands again.

## Organizing

- Sections group workspaces in the sidebar. A workspace without one is in Others. Use `list_sections`, `create_section`, `set_workspace_section`, `clear_workspace_section`, and `remove_section`; removing a section keeps its workspaces.
- Tags: `list_tags`, `upsert_tag` to create, rename, or recolor, `remove_tag`, `tag_workspace`, and `untag_workspace`.
- Parent and child links nest workspaces: `link_workspaces` and `unlink_workspaces`. `preview_workspace_cascade` lists the workspaces an action would reach through descendants and shared tags.

## Linked Issues

`link_workspace_issue` links one issue URL to a workspace, and `unlink_workspace_issue` removes it. `show_workspace_issue` reads it fresh from GitHub, GitLab, or Azure DevOps. `fetch_issue` reads any issue by URL. These use `gh`, `glab`, or `az` on the runtime's machine.

## Metadata Repair

`register_workspace_record` and `unregister_workspace_record` only write or delete Alera's record of a workspace. They never create or delete a worktree. Use them only when the user asks to repair metadata, never as a shortcut to create or remove a workspace.
