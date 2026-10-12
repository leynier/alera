# Remote Host Bootstrap

## Overview

A remote host is a machine the desktop runtime (the hub) reaches over SSH. Registering one saves an SSH target in the hub's runtime store; bootstrapping it installs the standalone `alera` runtime there. Bootstrap installs and validates the Alera runtime only: it does not itself create a Git worktree, a workspace, or a project checkout. The hub then keeps one persistent link to each host's runtime, and terminals, files, search, Git, pull requests, AI Assist and agent status for a workspace on that host run there. `docs/remote-hosts-hub.md` describes the hub model; this document covers installing, checking, updating and removing hosts.

Create tasks on a project folder registered on a host with `alera workspace add --host-id <id>` or Desktop New Workspace. Use `--worktree` for an exclusive Git worktree created by the host's runtime from that host's registered repository. Creation uses branches and remote-tracking references already present there; it does not upload a local Git bundle or fetch changes automatically. New workspaces record their repository of origin. Legacy remote worktrees retain their existing bare repository origin when a project folder is registered. `workspace.files.list` and `workspace.files.read` read that host's tree even when an identical path exists on the hub machine.

`alera workspace register --host-id` remains metadata only. It stamps a host id on a workspace record and does not create a remote Git worktree.

## Supported Targets

Bootstrap supports `x64` and `arm64` macOS, Linux, and Windows hosts reachable through the local OpenSSH tools. Authentication is limited to an SSH agent, a key configured in `~/.ssh/config`, or a key file saved on the host record (`identityFile`, passed to every `ssh` and `sftp` call as `-i <path> -o IdentitiesOnly=yes`; capability `sshTargetIdentityFileV1`). Password authentication is rejected at add, upsert, `bootstrap-plan`, and bootstrap with `password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.` Settings offers SSH Agent and Key File only, and a target saved with password login shows a notice asking to switch. Platform and architecture can be saved on the target or overridden per bootstrap, otherwise Alera probes the remote host.

Default install directories are:

- macOS/Linux: `~/.alera/sidecar`
- Windows: `%LOCALAPPDATA%\Alera\runtime`

The POSIX default keeps the runtime layout (`current/`, `bin/`, `versions/`, `data/`). It is separate from the CLI runtime profile (`ALERA_RUNTIME_DIR` or `~/.alera/runtime`). The install directory can be overridden from Settings or the CLI.

Quote `~/...` in the shell so the local runtime does not expand it before Alera sees the path. Absolute install directories are checked against the detected remote platform: a Linux `/home/...` path is rewritten to `/Users/...` on macOS (where `/home` is autofs), and POSIX home paths are rejected on Windows. Bootstrap errors keep the real path for debugging and redact credentials only.

## Artifact Trust

Release bootstrap uses a signed runtime archive from GitHub Releases. The archive lists each `alera-runtime-<version>-<platform>-<arch>.tar.gz` artifact with SHA-256 and size metadata, and the archive itself is signed with the same Ed25519 manifest key used by desktop update indexes. A release build passes that public key to the runtime through `ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY`.

Local development can pass `--artifact-path` to install a local tarball. That path is marked as a local override and is not treated as a signed release artifact.

## CLI

List hosts. With a running runtime each one carries its `hostStatus` (see Host Status And Lifecycle):

```bash
alera ssh-target --json list
```

Add a host. Duplicate aliases, including different casing, fail with `ssh target alias already exists: <alias>` using the attempted alias:

```bash
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
alera ssh-target --json add --alias build-linux --host 10.0.0.5 --username dev --auth key --identity-file "~/.ssh/build_linux"
```

`--auth password` is rejected with the same product error as bootstrap and does not persist the target. `add` only creates: an id that is already saved fails with `ssh target already exists: <id>` and points to `update`.

Change a saved host. Only the flags given change; an empty `--platform`, `--arch`, `--projects-dir`, or `--identity-file` clears that field, and the install directory, runtime version, and status are kept. Unknown ids fail with `ssh target not found`, and `--auth password` is rejected like `add`. Changing the address, port, user, authentication or identity file drops the current link:

```bash
alera ssh-target --json update --id <target-id> --host mac.lan --port 2222
```

Remove a saved host. Unknown ids fail with `ssh target not found`, matching `status` and `bootstrap-plan`. A host that still has projects or workspaces is refused, with or without a running runtime; remove them first:

```bash
alera ssh-target --json remove --id <target-id>
```

Probe live SSH connectivity and, when an install directory is known, the installed runtime. With a running runtime this goes through `sshTarget.check`, so the app refreshes and a host that should be linked connects now. The command persists `lastStatus` (`reachable`, `unreachable`, or `runtimeReady`) and updates `lastCheckedAt` on every call. Unknown ids still fail with `ssh target not found`:

```bash
alera ssh-target --json status
alera ssh-target --json status --id <target-id>
```

Preview, start, or cancel a bootstrap. Password targets fail with the same product error as bootstrap. When the runtime is running, `bootstrap` starts a job and returns immediately with a job id; without one, the CLI installs in the foreground and prints progress to stderr:

```bash
alera ssh-target --json bootstrap-plan --id <target-id>
alera ssh-target --json bootstrap --id <target-id>
alera ssh-target --json bootstrap-cancel --id <target-id>
```

Bootstrapping again reinstalls the release, but a runtime already running on the host keeps the version it started with until it stops. Use Update Runtime to switch it over.

`alera ssh-target link [--id <target-id>] [--connect | --disconnect]` lists, opens, or closes the hub's persistent link to a bootstrapped host's runtime. On the host, `alera runtime unlink-hub` makes its CLI list its own records again instead of the hub's.

## Host Status And Lifecycle

Every host the hub returns from `sshTarget.list`, `sshTarget.upsert` and `sshTarget.check` carries one `hostStatus` (capability `remoteHostStatusV1`), and the desktop, the phone and the CLI show that state instead of deriving their own:

| State | UI label | Meaning |
| --- | --- | --- |
| `needsSetup` | Needs Setup | The runtime was never installed, or the last install failed or was cancelled |
| `installing` | Installing… | An install or update job is running; `stage` names its step |
| `disconnected` | Not Connected | Installed, with no link open |
| `offline` | Offline | The machine could not be reached |
| `connecting` | Connecting… | A link attempt is running |
| `connected` | Connected, or Update Available | The link is attached; `runtimeUpdateAvailable` is true when the host runs an older runtime than the hub |
| `error` | Error | The link failed for another reason, such as a rejected key or a runtime that did not attach |

A failed or retrying link also reports `retry: {attempt, nextRetryAt}`. `sshTargetsChanged`, scoped by `hostId`, follows every change of a host's record or link, so the app and the phone refresh the state.

The hub keeps a link up while the host is desired: the runtime is installed and the host has an active workspace, or the user pressed Connect. Disconnect pauses the host until the next Connect, Check, endpoint edit, remote terminal or hub restart. A desired host that drops or fails to attach is retried on an exponential backoff with full jitter, from 2 s up to 300 s, except for failures retrying cannot fix. A link that is not desired, carries no terminal, and saw no use for 10 minutes is closed and reported Not Connected. Connecting never runs on the runtime's request loop.

`sshTarget.remove` refuses a host that still holds active workspaces or project checkouts with the conflict `sshTargetInUse {hostId, alias, workspaceCount, checkoutCount, projectIds, remoteOnlyProjectIds}`. On success it cancels a running install, sends `hub.unlink` over a live link so the host stops treating this hub as its source of truth, and drops the link. It never deletes the runtime or any files on the host.

## Update Runtime

Update Runtime installs a new runtime on a bootstrapped host and restarts the host's runtime onto it, so the host does not keep running the old binary until its next reboot. It is `sshTarget.bootstrap.start` with `restartRuntime: true` (capability `remoteRuntimeUpdateV1`); the request also accepts `id` in place of `targetId`. The job runs the ordinary install stages and then two more:

- `restart`: the hub reads the version the installed binary reports (`alera version --json` through `current`), stops the host's runtime with `host.shutdown` over the host link (`host.restart` would relaunch the old executable), waits up to 20 s for the link to close, and reconnects. The new `runtime-attach` goes through `bin/alera` to `current/alera`, so it starts the new runtime. It retries up to 10 times, 1.5 s apart, until the attached runtime reports the installed version; otherwise the job fails with `The runtime on <alias> still reports version <v> after the update. ...`.
- `prune`: every `versions/*` entry except the one just installed and the one `current` points at is deleted (POSIX `current` symlink, Windows `current.txt`). The script refuses to delete anything when it cannot tell which version is current. A failed prune is logged and never fails the job.

The final `installed` progress event is sent only after the restart and prune, and a failed job's final event carries the error. While hub terminals still run on the host, the request is refused before anything is installed with the conflict `hostBusy {hostId, alias, activeSessions, sessionIds}`; repeating it with `force: true` updates anyway and the restart closes those terminals. `force` is also passed to the satellite's `host.shutdown`, which otherwise refuses while its own terminals, agents or jobs are active.

`sshTarget.restartRuntime {id, force?}` runs only the restart and prune for a host whose runtime is already installed, with the same `hostBusy` rule. It is local-client-only, answers `{hostId, satelliteVersion}` once the restarted runtime has attached, and is refused while an install job runs on that host.

```bash
alera ssh-target --json update-runtime --id <target-id> [--force]
alera ssh-target --json restart-runtime --id <target-id> [--force]
alera ssh-target --json bootstrap --id <target-id> --restart-runtime [--force]
```

These go through the Alera runtime on this machine, starting it when needed, because the restart uses its host link. `update-runtime` installs the latest stable runtime and prints the job; `bootstrap --restart-runtime` takes the usual artifact flags. None of them is exposed as an MCP tool.

## Projects On A Host

Register an existing main project folder on a bootstrapped SSH host, then create independent tasks on it:

```bash
alera project --json hosts add --project-id <project-id> --host-id <target-id> --path <remote-absolute-path>
alera workspace add --project-id <project-id> --host-id <target-id> --name "First Task"
alera workspace add --project-id <project-id> --host-id <target-id> --name "Second Task"
```

Registration requires a host runtime supporting checkout inspection. It resolves the path on that host, checks directory access and the project's storage type, and preserves one project folder per project and host. Git projects require the main working directory of a non-bare repository. Registering a folder creates no task; adding a task starts with fresh state and does not run worktree setup, copy local files or change branches. Tasks use the remote checkout's current branch and files. Unavailable hosts and changed canonical paths fail without deleting existing records.

Create a managed Git worktree once the project folder is registered on that host. The command fails if the host is missing, not bootstrapped, or unreachable:

```bash
alera workspace add --worktree --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --host-id <target-id>
```

For a Git project without a checkout on that SSH host, clone directly on the host before registration:

```bash
alera project --json hosts add --project-id <project-id> --host-id <target-id> --path <new-remote-absolute-path> --clone-url <repository-url>
```

The destination's parent must exist. The host's runtime reserves a new destination and rejects existing directories, including empty ones and symlinks. Git uses that host's environment and credential helper with terminal prompting disabled. The runtime performs registration and cloning outside its actor loop so terminal requests can continue. If cloning fails or the response is lost, inspect the destination first: a completed clone can be registered by repeating `hosts add --path` without `--clone-url`. A partial destination is retained for inspection; another clone must use a new path. The CLI waits up to 30 minutes for the response; expiration does not confirm that remote work stopped.

To add a project to a host without choosing a destination, let the host pick one:

```bash
alera project --json hosts add --project-id <project-id> --host-id <target-id>
alera project --json hosts list --project-id <project-id>
alera project --json hosts remove --project-id <project-id> --host-id <target-id>
```

`hosts add` clones the Git remote of the local project folder (or `--clone-url <repository-url>`) into `<projects folder>/<project-folder-name>` on the host, where the projects folder is the target's `--projects-dir` (set with `alera ssh-target add --projects-dir` or in Settings > Remote Hosts) and defaults to `alera-projects` under the remote user's home, creating `alera-projects` when needed and taking the first free `<name>-N`. With `--path` it registers an existing checkout instead, and with `--path` and `--clone-url` it clones into exactly that folder as described above. A project already on the host is refused. `alera project register-checkout` remains only as a hidden alias of `hosts add --path [--clone-url]`. `hosts remove` forgets the checkout and never deletes files; it is refused while workspaces remain on that host. See `docs/remote-hosts-hub.md` for the model.

## Settings > Remote Hosts

Settings > Remote Hosts lists every host with one status (Needs Setup, Installing…, Not Connected, Offline, Connecting…, Connected, Update Available, Error) and its project and workspace counts. The detail of a host offers the one action its state calls for (Install Runtime, Connect, Disconnect, Update Runtime), Check Connection, and Edit Connection, Copy SSH Command and Remove Host in its overflow menu; it shows the install steps with Cancel Install while the runtime installs, the projects on that host, an Advanced group (install directory, projects folder, platform and architecture, and the identity file for key file login) with explicit Revert and Save, and Diagnostics with the last check, the last error and Open Logs Folder. Add Host is a guided dialog: Connection saves the alias, SSH Address (`user@host[:port]`) and authentication, Install Runtime checks the connection, shows what will be installed and follows the install, and Done offers to add a project to the host. Closing the dialog leaves a running install going. Remove Host is disabled while the host still has projects or workspaces and never deletes the runtime or files on the host. Update Runtime on a host with open terminals asks before closing them. Install progress is delivered through `sshTargetBootstrapProgress` events and the persisted target records the install directory, runtime version, platform, architecture, timestamps, and last redacted error. A successful bootstrap also stamps `lastStatus` as `runtimeReady`. `alera ssh-target status` then refreshes that live check independently of bootstrap.

Host status also shows outside Settings. Once a host is registered, the status bar carries a `Hosts 2/3` chip (connected over registered, with `· Installing…` while an install runs) whose card lists every host with its badge, a quick Connect, Retry or Update, and links to Remote Hosts and Add Host. A remote workspace row fades its host icon and names the state in its tooltip when the host is offline, failing or installing, and a project that lives only on a host shows that host's icon in its sidebar header. A connected host that drops raises one toast with Open Host, and a reconnect after it another, except for the host Settings is showing. An install that runs after its dialog was closed keeps a job card with Cancel, a failed one keeps a card with Retry and Dismiss, and a finished one raises a toast. New Workspace picks the host right after the project in both forms: hosts that cannot take a workspace yet stay listed but disabled with the reason (`(Needs Setup)`, `(Installing…)`, `(Error)`), an offline host stays selectable because the runtime connects on demand, and the list follows the hosts live while the form is open.

## Non-Goals

Bootstrap installs and validates the Alera runtime only. It does not install launchd, systemd, or Windows services, and it does not repair missing remote prerequisites beyond returning actionable failures. It does not create a workspace, a Git worktree, or a project checkout on the host.

Moving a workspace between hosts, syncing files between checkouts on different hosts, and password SSH authentication are out of scope. Git is the only channel between checkouts.

The installed runtime can also run on its own, without a desktop app:

```text
alera runtime start
alera runtime status
alera runtime agents enable codex claude
alera runtime agents status
alera runtime stop
alera runtime stop --force
alera runtime clear
alera runtime clear --force
```

`runtime start` launches a persistent detached host for the selected runtime directory. `runtime stop` refuses active terminal sessions and host jobs unless `--force` is present. `runtime clear` deletes the selected runtime profile only while its host is stopped; `--force` first stops a live host and can recover when its control file is missing. Clear removes runtime databases, credentials, logs, retained terminal history, and runtime metadata without deleting repositories, project folders, or worktrees. This lifecycle is portable and intentionally does not install a system service. Mobile gateway, pairing, workspace state, terminals, enabled agent integrations, `spawnOnCreate` tabs, and coordinator-created workers continue to operate directly against that host; see `docs/mobile-access.md`. Pairing can be completed entirely from the CLI with `alera mobile --json pairing create`; the desktop pairing dialog is optional.
