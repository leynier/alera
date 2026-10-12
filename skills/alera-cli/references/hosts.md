# Remote Hosts

## Model

A host is another machine this runtime reaches over SSH. The runtime you talk to is the hub; each host runs its own Alera runtime, installed by bootstrap. A project is registered once and then put on hosts: "project X on host Y" is one checkout row per host, and a workspace belongs to exactly one host. `local` is the hub's own machine. Workspaces never move between hosts, and Git is the only channel between checkouts on different hosts.

Hosts are managed with `alera ssh-target`. Every host id comes from `alera ssh-target --json list`. SSH authentication must come from an SSH agent, a key configured in `~/.ssh/config`, or a key file saved on the host with `--identity-file`; password authentication is rejected.

## Add And Edit A Host

```bash
alera ssh-target --json list
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
alera ssh-target --json add --id build-linux --alias build-linux --host 10.0.0.5 --username dev --auth key --identity-file "~/.ssh/build_linux" --projects-dir "~/code"
alera ssh-target --json update --id <host-id> --host mac.lan --port 2222
alera ssh-target --json remove --id <host-id>
```

- `add` only saves the record. It does not install anything or create a workspace. `--platform` and `--arch` are detected during bootstrap when omitted. `--projects-dir` is where the host clones projects when no path is given (default `alera-projects` under the remote home); quote `~/...` so your shell does not expand it.
- `--identity-file` is a private key path on this machine, passed to `ssh` and `sftp` as `-i` with `IdentitiesOnly`, so only that key is offered. A passphrase-protected key still has to be in the SSH agent.
- `add --id` with an id that is already saved fails with `ssh target already exists`. Use `update` to change a saved host: only the flags given change, an empty value clears `--platform`, `--arch`, `--projects-dir`, or `--identity-file`, and the installed runtime and its status are kept. Changing the address, port, user, authentication or identity file drops the current link. Bootstrap again if `--host` now names another machine.
- `remove` is refused while the host still has projects or workspaces, with the counts in the error, even without a running runtime. Remove its workspaces and take its projects off it first (`project hosts remove`, or remove a project that lives only there). Removing never uninstalls the runtime or deletes files on the host.
- Unknown ids fail with `ssh target not found`. Duplicate aliases, including different casing, fail with `ssh target alias already exists`.

## Install The Alera Runtime

```bash
alera ssh-target --json bootstrap-plan --id <host-id>
alera ssh-target --json bootstrap --id <host-id>
alera ssh-target --json bootstrap-cancel --id <host-id>
```

Bootstrap installs the signed Alera runtime release for the host's platform and architecture into `~/.alera/sidecar` (macOS and Linux) or `%LOCALAPPDATA%\Alera\runtime` (Windows); `--install-dir` overrides it. It does not create a Git worktree or a workspace. With a running runtime, `bootstrap` starts a job and returns at once; follow it in the app or with `status`. Without one, the CLI installs in the foreground and prints progress to stderr. `bootstrap-plan` previews the steps without changing the host.

Bootstrapping again installs the release again, but a runtime already running on the host keeps the version it started with until it stops. To switch it over, update instead.

## Update The Alera Runtime

```bash
alera ssh-target --json update-runtime --id <host-id>
alera ssh-target --json restart-runtime --id <host-id>
alera ssh-target --json bootstrap --id <host-id> --restart-runtime
```

`update-runtime` installs the latest stable runtime, restarts the host's runtime onto it, checks that the restarted runtime reports the installed version, and removes older versions from the host. It starts a job and returns at once; follow it with `status`. `restart-runtime` only restarts onto the version already installed and returns when the host answers again. `bootstrap --restart-runtime` does the same as `update-runtime` with the usual bootstrap flags. All three need this machine's runtime and start it when needed.

While terminals are open on the host they are refused with `hostBusy`, naming how many would close. Ask the user before adding `--force`, which updates anyway and closes them.

## Status

```bash
alera ssh-target --json list
alera ssh-target --json status
alera ssh-target --json status --id <host-id>
```

With a running runtime, every host in `list` and `status` carries `hostStatus`, the one state the app and the phone show:

| `hostStatus.state` | App label | Next step |
| --- | --- | --- |
| `needsSetup` | Needs Setup | `bootstrap` (the install never finished, failed, or was cancelled; `detail` has the last error) |
| `installing` | Installing… | Wait; `stage` is the current step (`auth`, `detect`, `artifact`, `upload`, `install`, `validate`, then `restart` and `prune` for an update) |
| `disconnected` | Not Connected | Nothing: the link opens when needed, or `link --connect` |
| `offline` | Offline | Check the machine and the network; the hub retries a host it needs |
| `connecting` | Connecting… | Wait |
| `connected` | Connected | Ready. `runtimeUpdateAvailable: true` means Update Available: run `update-runtime` |
| `error` | Error | Read `detail`, often a refused key or a runtime that did not attach, then fix and run `status` |

`hostStatus` also carries `satelliteVersion` (the host's runtime), `hubVersion`, `lastCheckedAt`, and `retry` (`{attempt, nextRetryAt}` while a dropped link waits to retry).

`status` probes SSH connectivity and, when a runtime is installed, checks it. It records `lastStatus` (`reachable`, `unreachable`, or `runtimeReady`) and `lastCheckedAt` on every call. With a running runtime it is the app's Check Connection: the app refreshes and a host that should be linked connects now. Without `--id` it probes every saved host and returns an array.

## Link

```bash
alera ssh-target --json link
alera ssh-target --json link --id <host-id> --connect
alera ssh-target --json link --id <host-id> --disconnect
```

The hub keeps at most one persistent link per host: one `ssh` connection to that host's Alera runtime that carries requests and events. Terminals each use their own SSH channel. A host with an installed runtime and an active workspace, or one connected with `--connect`, stays linked, and a dropped link is retried with a backoff that grows from 2 seconds to 5 minutes. Any other link opens when a remote workspace needs it, such as opening a terminal or reading files, and closes after 10 minutes without use. `--connect` also starts the host's runtime when needed. `--disconnect` closes the link and stops the hub from reconnecting it until the next `--connect`, `status`, or terminal on that host. `link` without flags lists each link with its state (`disconnected`, `connecting`, `attached`, or `failed`), the last error, `retry`, and whether the host is `desired` or `paused`.

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
