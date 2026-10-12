# Remote Hosts

## Model

A host is another machine this runtime reaches over SSH. The runtime you talk to is the hub; each host runs its own Alera runtime, installed by bootstrap. A project is registered once and then put on hosts: "project X on host Y" is one checkout row per host, and a workspace belongs to exactly one host. `local` is the hub's own machine. Workspaces never move between hosts, and Git is the only channel between checkouts on different hosts.

Hosts are managed with `alera ssh-target`. Every host id comes from `alera ssh-target --json list`. SSH authentication must come from an SSH agent or a key configured in `~/.ssh/config`; password authentication is rejected.

## Add And Edit A Host

```bash
alera ssh-target --json list
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
alera ssh-target --json add --id build-linux --alias build-linux --host 10.0.0.5 --username dev --auth key --projects-dir "~/code"
alera ssh-target --json update --id <host-id> --host mac.lan --port 2222
alera ssh-target --json remove --id <host-id>
```

- `add` only saves the record. It does not install anything or create a workspace. `--platform` and `--arch` are detected during bootstrap when omitted. `--projects-dir` is where the host clones projects when no path is given (default `alera-projects` under the remote home); quote `~/...` so your shell does not expand it.
- `add --id` with an id that is already saved fails with `ssh target already exists`. Use `update` to change a saved host: only the flags given change, an empty value clears `--platform`, `--arch`, or `--projects-dir`, and the installed runtime and its status are kept. Bootstrap again if `--host` now names another machine.
- Unknown ids fail with `ssh target not found`. Duplicate aliases, including different casing, fail with `ssh target alias already exists`.

## Install The Alera Runtime

```bash
alera ssh-target --json bootstrap-plan --id <host-id>
alera ssh-target --json bootstrap --id <host-id>
alera ssh-target --json bootstrap-cancel --id <host-id>
```

Bootstrap installs the signed Alera runtime release for the host's platform and architecture into `~/.alera/sidecar` (macOS and Linux) or `%LOCALAPPDATA%\Alera\runtime` (Windows); `--install-dir` overrides it. It does not create a Git worktree or a workspace. With a running runtime, `bootstrap` starts a job and returns at once; follow it in the app or with `status`. Without one, the CLI installs in the foreground and prints progress to stderr. `bootstrap-plan` previews the steps without changing the host.

Bootstrapping again installs the release again, but a runtime already running on the host keeps the version it started with until it stops.

## Status

```bash
alera ssh-target --json status
alera ssh-target --json status --id <host-id>
```

`status` probes SSH connectivity and, when a runtime is installed, checks it. It records `lastStatus` (`reachable`, `unreachable`, or `runtimeReady`) and `lastCheckedAt` on every call. Without `--id` it probes every saved host and returns an array.

## Link

```bash
alera ssh-target --json link
alera ssh-target --json link --id <host-id> --connect
alera ssh-target --json link --id <host-id> --disconnect
```

The hub keeps at most one persistent link per host: one `ssh` connection to that host's Alera runtime that carries requests and events. Terminals each use their own SSH channel. The link opens on its own when a remote workspace needs it, such as opening a terminal or reading files; `--connect` opens it ahead of time and starts the host's runtime when needed, and `--disconnect` closes it. `link` without flags lists each link with its state (`disconnected`, `connecting`, `attached`, or `failed`) and the last error.

## Put A Project On A Host

```bash
alera project --json list
alera project --json hosts list --project-id <project-id>
alera project --json hosts add --project-id <project-id> --host-id <host-id>
alera project --json hosts add --project-id <project-id> --host-id <host-id> --path <existing-absolute-path>
alera project --json hosts add --project-id <project-id> --host-id <host-id> --path <new-absolute-path> --clone-url <repository-url>
alera project --json hosts remove --project-id <project-id> --host-id <host-id>
alera project --json add-remote --host-id <host-id> --path <existing-absolute-path>
alera project --json add-remote --host-id <host-id> --clone-url <repository-url>
```

- `project list` shows `primaryHostId` and `checkouts` for each project. The primary host is where the project's own folder is: `local` for an ordinary project.
- `hosts add` has three forms. Without `--path` the host clones the project's Git remote, or `--clone-url`, into its projects folder under the project folder's name (first free `<name>-N`). With `--path` alone it registers a checkout that already exists there. With `--path` and `--clone-url` it clones into exactly that new folder; its parent must exist and the folder itself must not. The host must have the Alera runtime installed. Clones use the host's own Git credentials, and the CLI waits up to 30 minutes.
- Only Git projects can be on more than one host. A project already on a host is refused, and so is `local` (register the local folder as its own project instead).
- `hosts remove` forgets the checkout and never deletes files. It is refused while workspaces remain on that host, for the project's only host, and for its primary host.
- `add-remote` registers a project that lives only on a host, from an existing folder or by cloning into the host's projects folder. That host becomes its primary host. A worktree on such a project needs an explicit `--source-branch`.
- If a clone fails or its answer is lost, inspect the destination first. A finished clone can be registered with `hosts add --path` and no `--clone-url`; a partial one is kept, and another clone needs a new path.

## Workspaces On A Host

```bash
alera workspace add --project-id <project-id> --host-id <host-id> --name "First Task"
alera workspace add --project-id <project-id> --host-id <host-id> --worktree --branch <new-branch> --source-branch <source-branch>
alera workspace list --project-id <project-id> --host-id <host-id>
```

- `--host-id` on `workspace add`, `workspace start`, and `workspace prompt-start run` picks the host. Omit it for the project's primary host. The project must already be on that host.
- Without `--worktree` the workspace shares the project folder on that host and its current branch. With `--worktree` the host creates the Git worktree from its own repository, using branches already there; nothing is uploaded or fetched automatically.
- Terminals, files, search, Git, pull requests, and agent status for the workspace run on that host. Commands fail with an actionable error when the host is unknown, has no runtime installed, or is unreachable.
- `workspace register --host-id` only writes metadata and never creates a remote worktree.

## Inside A Terminal On A Host

A terminal on a host runs that host's `alera`. Once the host serves a hub workspace, its CLI works against the hub's state through the link:

- `project list`, `workspace list`, and `tag list` answer from the hub. `--host-id origin` means the host the terminal runs on.
- Workspace, project host, tag, section, agent profile, orchestration, issue, and pull request watch commands are sent to the hub and change its state. Omitting `--host-id` on `workspace add`, `workspace start`, `project hosts add`, and `project add-remote` means this host.
- Terminal commands, `ssh-target`, account, runtime settings, mobile, and automation commands are not forwarded; run them on the hub's machine.
- With no hub linked the command fails and says to connect the host from the desktop, instead of answering from the host's partial copies.
