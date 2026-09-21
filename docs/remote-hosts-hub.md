# Remote Hosts Hub

This document is the specification and progress tracker for cross-platform remote workspaces: one project registered on several SSH hosts, every desktop feature working against the host that owns the checkout, and one `alera` CLI that sees the whole picture. It complements `docs/remote-host-bootstrap.md` (installing the sidecar) and `docs/shared-checkout-implementation.md` (the shared-checkout model). Statements in the progress table are the only claims about what is implemented; everything else describes the target.

## Spec

### Goals

- Any direction works: the desktop (hub) may run on macOS, Windows, or Linux, and a registered host may run any of the three. Remote command construction, path joining, quoting, and shell selection are decided per remote platform, never assumed from the hub platform.
- One project, many hosts. A Git project is registered once and then added to hosts. The mental model is "work on project X on host Y", not "project X1 and X2". Folder (non-Git) projects live on exactly one host.
- A project may have no local checkout at all: a repository that exists only on a server is still a first-class project.
- Every workspace feature works when the workspace lives on another host: terminals, agent launch and status, Explorer including writes, Source Control, Pull Request, Find and Replace in Files, Quick Open, AI Assist, Watch and Fix, orchestration, resource monitoring.
- Remote workspace rows in the sidebar show the host operating system as an icon (Apple, Windows, Linux penguin) whose tooltip names the host alias. Local workspaces show no host icon.
- The CLI lists and manages workspaces on every host from the hub, and the CLI running inside a remote terminal (typically an agent) sees and manages the same federated state.

### Non-goals

- Moving a workspace between hosts (Hand Off / Hand On stay within one host).
- Synchronizing files between checkouts on different hosts; Git is the only channel between them.
- Password SSH authentication; agent or key authentication remains the only supported mode.
- Peer-to-peer topologies where two desktops own overlapping state. There is exactly one hub per user setup.

### Constraints

- Neither `aleraTerminalHostProtocolVersion` nor `aleraMobileProtocolVersion` changes. Every new verb, event, and field is additive and gated by a capability.
- An older sidecar on a remote host keeps working through the existing per-terminal `ssh -tt` path until it is re-bootstrapped. The hub feature-detects the remote runtime's capabilities.
- Hub-owned records remain the source of truth. The remote runtime holds mirrored copies only for the workspaces the hub asked it to serve.
- Secrets never cross hosts: forge and AI CLIs run on the host that owns the checkout with that host's credentials; the hub never stores or relays tokens.

## Design

### Topology

The desktop runtime is the **hub**. Every bootstrapped SSH target runs one **satellite** runtime: the sidecar's `alera runtime-host` on its own profile at `<installDir>/data` (the `bin/alera` wrapper already exports that as `ALERA_RUNTIME_DIR`). The per-project `owners/<sha256(projectId)>` profiles are retired for new terminals; existing ones are drained (see compatibility).

### Host link

The hub keeps at most one **host link** per SSH target: a single `ssh` child running `alera runtime-attach --stdio` on the remote. That command connects to the satellite runtime (starting it persistent when needed), performs the `hello` locally with the satellite's token, and then pipes newline-delimited JSON between its stdio and the runtime socket. The hub therefore speaks the ordinary runtime-host protocol to the satellite without ever learning the satellite's token, and without a second protocol.

- `rust/alera-cli/src/terminal_host/host_link.rs` owns the hub side of one link: the `ssh -T` child (keep-alives on, no PTY), request correlation by id, event fan-in as `ServerCommand::HostLinkEvent`, and close detection as `ServerCommand::HostLinkClosed`, which fails every pending request. `host_link_registry.rs` keeps one link per host id, opens it on demand from a spawned task (the actor never awaits the ssh handshake), dedupes concurrent connects behind a per-host lock, and publishes `HostLinkStateChanged`. The launcher that produces the process is injectable, so tests stand a local script in for `ssh`.
- `rust/alera-cli/src/runtime_attach.rs` owns the satellite side command. It never requests binary frames, so the pipe stays line oriented. Its first stdout line is the `hostLink.attached` event (runtime dir, platform, arch, host version, capabilities); the hub refuses any other first frame. Exit code 0 means the hub closed the pipe, 1 means the satellite runtime went away.
- The remote command goes through the sidecar's `bin/alera` wrapper so `ALERA_RUNTIME_DIR` points at the sidecar data profile. POSIX uses `sh -lc` with tilde expansion of the stored install dir. Windows deliberately runs `"<installDir>\bin\alera.cmd" runtime-attach --stdio` under the sshd default shell (`cmd.exe`) and never through PowerShell: when PowerShell's own stdin is redirected it gives a native command an empty pipe unless the command sits on the right of `|`, so frames written by the hub would never reach `alera.exe`. A Windows target whose sshd `DefaultShell` is PowerShell cannot carry a link; the attach fails with the ssh stderr tail in the error.
- Verbs (local clients only, all deferred except status): `hostLink.status` (`{links: [{hostId, state, attachment?, error?}]}` with `state` in `disconnected | connecting | attached | failed`), `hostLink.connect {hostId}`, `hostLink.disconnect {hostId}`, and `hostLink.request {hostId, type, payload, timeoutMs?}`, which forwards one verb to the satellite and returns its answer with the error shape preserved (`FormatException:` prefix and `errorCode` / `errorDetails` survive the hop). Events: `hostLinkChanged` (the state payload plus `hostId`) and `hostLinkEvent` (`{hostId, event, payload}` for anything the satellite pushes). Both names are in `runtimeHostEventNames`.
- `alera ssh-target link [--id <host>] [--connect | --disconnect]` drives the same verbs from the CLI. Settings > Remote Hosts shows a Host Link group for bootstrapped targets with the state, the satellite version and platform, and Connect / Disconnect.
- Capability `remoteHostLinkV1` is advertised by hubs that can open links. `remoteSatelliteV1` says the runtime accepts `runtime-attach`; the mirror and hub-forwarding verbs of later phases are gated by their own capabilities once they land. Neither bumps `aleraTerminalHostProtocolVersion`.

### Mirroring

Before the hub asks a satellite to do anything for a workspace, it registers the project and workspace there through `hub.mirror.workspace`. The payload is the `{project, workspace, repositoryPath?}` document the legacy `alera project owner-terminal --metadata-base64` command carried, built by `remote_owner_terminal_launch::satellite_registration` (project path = the checkout registered for that host, `repositoryPath` = the verified origin of a linked worktree), and the satellite runs it through the same `remote_workspace_owner::register` validation: it adopts the hub's project, workspace and instance ids, points the project at its local checkout, stores the workspace with `hostId = local`, and refuses to replace a record whose identity differs. The verb is idempotent and local-client-only on the satellite.

On the hub, `server/host_link_routing.rs` is the entry point for every host-scoped verb: `remote_workspace` resolves a workspace and rejects local ones, and `mirror_workspace` opens or reuses the link, mirrors, and returns the link plus the satellite's copy of the record (whose `path` is canonical on that host). `hostLink.mirrorWorkspace {workspaceId}` exposes it directly so the CLI and tests can exercise the round trip. Retiring a remote workspace keeps going through the existing owner retirement flow (`workspace.removeShared` / `removeManaged` on the satellite with process-closure evidence); a `hub.mirror.retire` shortcut is not needed.

### Terminal proxy

Remote terminals keep one `ssh -tt` channel per PTY, running `alera project owner-terminal` on the satellite. Multiplexing PTY bytes over the single link would frame every output chunk twice (satellite queue, then hub queue) for no gain, since OpenSSH already opens one channel per session; the link carries requests and events, the per-terminal channel carries the stream. What changed is where that terminal lives: `owner_command_script` now targets the satellite profile at `<installDir>/data` for every owner command (terminal, precheck, relocation, retirement), so the session is created in the same runtime the link attaches to and every satellite-side feature (agent hooks, resource sampling, Terminal Pulse, git and files in later phases) sees the same workspace and session records. The `owner-terminal` command starts the satellite runtime when none is running, and `runtime-attach` connects to it, so the two paths converge on one runtime per host.

### Host-scoped work

Every verb that needs the checkout's filesystem or tools is answered by the host that owns the workspace. On the hub, a `WorkspaceHost` resolver maps a workspace id to `Local` or `Linked(hostId)`; local requests take the current code path and linked requests are forwarded unchanged (the satellite sees `hostId = local`).

| Area | Verbs on the satellite | Desktop seam |
| --- | --- | --- |
| Files | `workspace.files.list/read/write/create/rename/delete/stat` | `WorkspaceFileService` already routes reads; writes stop refusing remote workspaces. |
| Search and Quick Open | `workspace.search.*`, `workspace.quickOpen.*` (same `alera_core::workspace_search` and file catalog mobile already uses) | `WorkspaceSearchController` and quick open choose the runtime path when the workspace is remote. |
| Git | `git.*` covering the `GitBackend` interface, implemented with `alera_core::source_control` and `git_in_dir` | `RuntimeGitBackend` implements `GitBackend` over the runtime client; `gitBackendForWorkspace` picks it for remote workspaces. Services keep depending on `GitBackend`. |
| Processes | `host.process.run` (executable, arguments, cwd, stdin, environment names) | `RemoteProcessRunner` implements `ProcessRunner`; Pull Request forge providers, Open in Browser, and other CLI-backed features take a per-workspace runner. Never on the mobile allowlist. |
| AI Assist | `aiText.*` forwarded when the request names a remote workspace | none, the hub decides. |
| Agent status and titles | Satellite hook receiver reports as today; `agentStatusChanged` and title events are relayed by the hub with the hub's workspace ids | none, the existing controllers receive the same events. |
| Resources | `resources.snapshot` forwarded and merged, rows tagged with `hostId` | Resource Manager shows remote rows with metrics instead of dashes. |
| Watch and Fix | `pull_request_watch_evaluation` runs forge and Git commands through a `HostCommandRunner` (`Local` or `Linked`) | none. |
| Orchestration | Worker spawn and prompt injection use the terminal proxy | none. |

### Project on many hosts

- `projects.primaryHostId` (additive, default `local`) names the host of `projects.repoPath`. A project whose only checkout is remote stores that host and path. Every desktop and CLI code path that treats `repoPath` as a local directory first checks `primaryHostId == local`.
- `project.list` includes `checkouts: [{hostId, path}]` from `repositoryCheckouts`; the Dart `Project` gains `primaryHostId` and `checkouts`.
- `project.hosts.add` registers or clones a project on a host: with `path` it registers an existing checkout (existing `project.checkout.register`), without it the satellite clones the project's remote URL into `<projectsDir>/<projectName>` where `projectsDir` is a new per-target setting defaulting to `~/alera-projects` (POSIX) or `%USERPROFILE%\alera-projects` (Windows). `project.hosts.remove` unregisters without deleting files and refuses while workspaces exist on that host.
- Desktop: a **Hosts** action on the project shows its checkouts with Add and Remove; New Workspace's host picker lists the hosts the project is on, plus an "Add to Host" entry that runs the clone job first. Branch validation uses the per-host branch catalog, never the local `repoPath`.
- Folder projects refuse `project.hosts.add`.

### Sidebar and design system

`AleraHostOsIcon` in `lib/src/design_system/icons/` renders Apple, Windows, or Linux glyphs from a `HostOs` enum (`macos`, `windows`, `linux`, `unknown`), with a co-located preview. The workspace row and `WorkspaceGraphChips` resolve `SshTarget.runtimePlatform ?? platform` through the `sshTargets` provider and show the icon with the alias as tooltip; unknown platforms fall back to the generic host icon.

### CLI

- `alera project list` prints checkouts per host; `alera project hosts list|add|remove` manages them (`register-checkout` stays as an alias of `hosts add --path`).
- `alera workspace list --host-id <id>` filters by host.
- Inside a remote terminal the CLI reaches the satellite. In satellite mode every hub-owned verb (projects, workspaces, tags, sections, agent profiles, orchestration, issues) is forwarded to the hub over the link as a reverse request (`hub.request` event answered by `hub.respond`), stamped with `originHostId` so the hub defaults `hostId` to that satellite. When no hub is linked the CLI fails with an actionable message rather than acting on mirrored copies.

### Cross-platform rules

- Remote command lines are built by `RemoteShell::{Posix, Windows}` builders in one module; Windows uses `powershell -EncodedCommand` for scripts and PowerShell single-quoted strings for arguments, POSIX uses `sh -lc` with `shell_quote`.
- Paths are joined with the remote platform's separator (`join_remote`), never `std::path`.
- The hub spawns `ssh` through `windowless_async_command` with `BatchMode=yes` and `GIT_TERMINAL_PROMPT=0` semantics preserved.
- Unit tests build every command for both remote shells, and the acceptance pass runs Linux hub against macOS and Windows targets plus Windows hub against a Linux target.

### Compatibility

- Per-project `owners/<sha256(projectId)>` profiles are no longer written. A workspace created before the switch has its sessions and retirement receipt in that profile, so `alera project owner-retire` looks the workspace up in the satellite profile first and falls back to the legacy profile next to it that knows the workspace and instance (`remote_owner_retirement::owning_state_dir`); a legacy runtime that stays idle shuts itself down through the normal empty-host delay. Opening a terminal on such a workspace mirrors it into the satellite and continues there.
- Older hubs ignore the new fields; older satellites reject unknown verbs with the existing `unknown terminal host request` error, which the desktop maps to an "update the sidecar" message.

## Tasks

| # | Task | Status |
| --- | --- | --- |
| 0 | Plan document, `AleraHostOsIcon`, sidebar icon and alias tooltip, graph chip icon | Completed |
| 1 | `alera runtime-attach --stdio` and hub `HostLink` / `HostLinkRegistry`; `hostLink.*` verbs, `hostLinkChanged`; capabilities `remoteHostLinkV1` and `remoteSatelliteV1`; CLI `ssh-target link`; Settings Host Link group | Completed |
| 2 | `hub.mirror.workspace` on the satellite, `host_link_routing` and `hostLink.mirrorWorkspace` on the hub, owner commands retargeted to the satellite profile, legacy owner-profile fallback for retirement | Completed |
| 3 | Files write verbs, search, quick open over the link; desktop routing | Pending |
| 4 | `git.*` verbs and `RuntimeGitBackend`; Source Control on remote workspaces | Pending |
| 5 | `host.process.run`, `RemoteProcessRunner`, Pull Request and Open in Browser on remote; AI Assist and Watch and Fix routed by host | Pending |
| 6 | Agent status, titles, and resource relay | Pending |
| 7 | `primaryHostId`, `checkouts` in project payloads, `project.hosts.*`, Hosts dialog, New Workspace "Add to Host", remote-only projects | Pending |
| 8 | CLI: `project hosts`, `workspace list --host-id`, satellite forwarding to the hub | Pending |
| 9 | Mobile: OS icon and alias tooltip, remote workspace actions allowed | Pending |
| 10 | Documentation, unit and integration tests, real-machine acceptance matrix | Pending |

## Tests

- Rust unit tests for every remote command builder on both shells, the link framing and reconnect logic, the mirror validation, the forwarding decision (`host_link_routing::remote_workspace`), and the satellite request forwarding policy.
- Rust integration tests that run two runtime hosts (hub and satellite) with an `ssh` script that executes the remote command locally, so the hub's real launcher, the sidecar `bin/alera` wrapper and `runtime-attach` are all exercised (`tests/terminal_host_headless_runtime/host_link_mirror_case.rs`); later phases add files, git, and process verbs to that harness.
- Dart unit tests for `RuntimeGitBackend`, `RemoteProcessRunner`, `gitBackendForWorkspace`, host icon resolution, and the project checkout model; widget tests for the sidebar icon and tooltip, the Hosts dialog, and the New Workspace picker.
- Real-machine acceptance from the Linux hub against the macOS and Windows targets: create workspace, terminal, agent launch with status, edit and save a file, stage and commit, open the pull request panel, search, and `alera workspace list` from inside the remote terminal.

## Assumptions

- The remote host has OpenSSH server and, on Windows, PowerShell 5.1 or newer; `pwsh` is optional.
- The hub can reach the host by SSH with agent or key authentication configured in `~/.ssh/config`.
- The satellite runtime keeps running detached after the link drops; idle shutdown is governed by the sidecar's persistent lifecycle.
- Mirrored records on the satellite are disposable; deleting `<installDir>/data` loses no hub-owned state.

## Progress

Updated as work lands. Only rows marked Completed describe implemented behavior.

| Step | Outcome | Status |
| --- | --- | --- |
| Analysis | Mapped the existing remote implementation and its gaps | Completed |
| Decisions | Hub topology, persistent link, auto-clone registration, remote-only projects, remote-only icon, hub-forwarded CLI | Completed |
| Phase 0 | `AleraHostOsIcon` (Apple, Windows, Linux) in the sidebar workspace row, host picker and Remote Hosts list; alias tooltip | Completed |
| Phase 1 | Host link: `runtime-attach --stdio`, `HostLink` / `HostLinkRegistry`, `hostLink.*` verbs and events, capabilities, CLI and Settings surface. Verified with unit tests (both remote shells, framing, error shapes, registry states), a fake-satellite link round trip, and a binary conformance test that attaches to a real local runtime host | Completed |
| Phase 2 | Satellite mirror (`hub.mirror.workspace`), hub routing (`host_link_routing`, `hostLink.mirrorWorkspace`), all owner commands on the satellite profile `<installDir>/data`, retirement fallback to legacy `owners/` profiles. Verified with a two-runtime headless test that mirrors over a real link (idempotent, satellite record visible, unknown workspace rejected, link reported attached with the satellite's runtime dir), the owner terminal and home retirement headless cases on the shared profile, and a unit test for the legacy fallback | Completed |
