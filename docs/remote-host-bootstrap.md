# Remote Host Bootstrap

Alera can register SSH targets in the Home Runtime and install the standalone `alera` runtime sidecar on those hosts. Bootstrap is sidecar only: it installs and validates the runtime sidecar and does not itself create a Git worktree.

Create a managed Git worktree on a bootstrapped host with `alera workspace add --host-id <id>` or from Desktop New Workspace by picking that host. The Home Runtime copies the project as a git bundle, creates the worktree on that host (posix or Windows, using the same SSH path as bootstrap), and stores the workspace with that host id. Terminals for that workspace spawn `ssh` into the remote worktree. `workspace.files.list` and `workspace.files.read` read the remote tree over SSH.

`alera workspace register --host-id` remains metadata only. It stamps a host id on a workspace record and does not create a remote Git worktree.

## Supported Targets

Bootstrap supports `x64` and `arm64` macOS, Linux, and Windows hosts reachable through the local OpenSSH tools. Authentication is intentionally limited to SSH agent or key configuration in `~/.ssh/config`. Password authentication is rejected at add, upsert, `bootstrap-plan`, and bootstrap with `password SSH targets are not supported for bootstrap; configure SSH agent or key authentication.` Settings keeps Password listed but disabled for new targets. Platform and architecture can be saved on the target or overridden per bootstrap, otherwise Alera probes the remote host.

Default install directories are:

- macOS/Linux: `~/.alera/sidecar`
- Windows: `%LOCALAPPDATA%\Alera\runtime`

The POSIX default is the sidecar layout (`current/`, `bin/`, `versions/`, `data/`). It is separate from the CLI runtime profile (`ALERA_RUNTIME_DIR` or `~/.alera/runtime`). The install directory can be overridden from Settings or the CLI.

Quote `~/...` in the shell so the local Home Runtime does not expand it before Alera sees the path. Absolute install directories are checked against the detected remote platform: a Linux `/home/...` path is rewritten to `/Users/...` on macOS (where `/home` is autofs), and POSIX home paths are rejected on Windows. Bootstrap errors keep the real path for debugging and redact credentials only.

## Artifact Trust

Release bootstrap uses a signed runtime archive from GitHub Releases. The archive lists each `alera-runtime-<version>-<platform>-<arch>.tar.gz` artifact with SHA-256 and size metadata, and the archive itself is signed with the same Ed25519 manifest key used by desktop update indexes. A release build passes that public key to the runtime host sidecar through `ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY`.

Local development can pass `--artifact-path` to install a local tarball. That path is marked as a local override and is not treated as a signed release artifact.

## CLI

List targets:

```bash
alera ssh-target --json list
```

Add a target. Duplicate aliases, including different casing, fail with `ssh target alias already exists: <alias>` using the attempted alias:

```bash
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
```

`--auth password` is rejected with the same product error as bootstrap and does not persist the target.

Remove a saved target. Unknown ids fail with `ssh target not found`, matching `status` and `bootstrap-plan`:

```bash
alera ssh-target --json remove --id <target-id>
```

Probe live SSH connectivity and, when an install directory is known, the remote runtime sidecar. The command persists `lastStatus` (`reachable`, `unreachable`, or `runtimeReady`) and updates `lastCheckedAt` on every call. Unknown ids still fail with `ssh target not found`:

```bash
alera ssh-target --json status
alera ssh-target --json status --id <target-id>
```

Preview a bootstrap. Password targets fail with the same product error as bootstrap:

```bash
alera ssh-target --json bootstrap-plan --id <target-id>
```

Start a bootstrap:

```bash
alera ssh-target --json bootstrap --id <target-id>
```

Create a managed Git worktree on that host after bootstrap succeeds, from the CLI or Desktop New Workspace:

```bash
alera workspace add --project-id <project-id> --branch <new-branch> --source-branch <source-branch> --host-id <target-id>
```

The command fails if the target is missing, not bootstrapped, or unreachable.

Cancel an active runtime-host bootstrap job:

```bash
alera ssh-target --json bootstrap-cancel --id <target-id>
```

When the runtime host is running, `bootstrap` starts a host job and returns immediately with a job id. Without a runtime host, the CLI performs the bootstrap in the foreground and prints progress to stderr.

`alera ssh-target` has no connect or disconnect verbs. Bootstrap still does not place a Git worktree; use `alera workspace add --host-id` or New Workspace for that.

## Mobile Access

Mobile companion pairing is managed from **Settings → Mobile Devices** in the desktop app: enable the gateway, tune bind host/port, generate a pairing offer rendered as a QR code (with a copy-JSON fallback), watch active offers with their expiry, and rename or revoke paired devices. The pane pre-validates custom endpoints with the same rules the runtime enforces and updates live through the `mobileSettingsChanged`, `mobilePairingsChanged`, `mobileDevicesChanged`, and `mobileGatewayChanged` events. The equivalent CLI surface remains available:

```bash
alera mobile --json enable --bind-host 127.0.0.1 --port 6768
alera mobile --json pairing create --endpoint wss://<host-or-vpn-name>:6768
alera mobile --json pairing cancel --id <pairing-id>
alera mobile --json devices list
alera mobile --json devices rename --id <device-id> --name <new-name>
alera mobile --json devices revoke --id <device-id>
alera mobile --json devices delete --id <device-id>
alera mobile --json disable
```

The generated pairing payload can be pasted or scanned in the Flutter app under `mobile/`. The CLI starts or reuses a mobile-capable runtime host for enable and pairing creation so the WebSocket listener is live before a pairing payload is returned. The app opens the configured WebSocket endpoint, claims the pairing offer with `mobile.device.pair`, stores the returned device token in secure storage, then authenticates future sessions with `mobile.hello`. Runtimes advertising `mobileWorkspaceSidebarParityV1` expose a sidebar snapshot with projects, workspaces, tags, shared view preferences, shared activity, runtime settings, and agent presence. Those clients can also rename, pin, sleep, tag, link/unlink, create, and remove managed workspaces, open the repository URL on the phone, copy the host path, and create or attach to terminal sessions. Sleep always confirms and asks the host to remove every tab and layout entry for the selected workspace and terminate its terminal sessions while preserving its branch and files. A runtime released before the close-all Sleep behavior can retain tab records until that host is updated. Older runtimes are blocked from the parity workspace screen and must be updated instead of silently showing a reduced feature set. Mobile access defaults to a loopback bind. Plain `ws://` endpoints are accepted only for loopback/local development because pairing secrets and device tokens are bearer credentials; their explicit port must match the local gateway port. Phone/LAN/VPN access should expose the loopback gateway through a TLS tunnel or proxy and advertise `wss://`; the public TLS endpoint port can differ from the local gateway port. When intentionally binding `0.0.0.0`, pass a reachable `--endpoint` because the pairing payload cannot advertise a wildcard address. Device revocation, permanent deletion of revoked device records, device rename, and pairing-offer cancellation are host-side operations (settings pane, CLI, or runtime-host RPCs `mobile.device.revoke`, `mobile.device.delete`, `mobile.device.rename`, `mobile.pairing.cancel`); they are excluded from the mobile request allowlist, and revocation immediately disconnects active sessions for the revoked device. Delete only removes already-revoked records from the list. The pairing secret is returned only once at creation time, so the QR for an existing offer cannot be shown again - cancel it and generate a new one instead.

## Settings

Settings includes a **Remote Hosts** section for adding SSH targets, choosing optional platform/architecture/install directory overrides, previewing the bootstrap plan, starting bootstrap, and cancelling an active job. The pane states that bootstrap installs the sidecar only and does not create remote workspaces. Bootstrap progress is delivered through runtime-host events and the persisted target status records the install directory, runtime version, platform, architecture, timestamps, and last redacted error. A successful bootstrap also stamps `lastStatus` as `runtimeReady`. `alera ssh-target status` then refreshes that live check independently of bootstrap.

Settings also includes a **Mobile Devices** section covering the full mobile companion lifecycle: gateway enable/bind host/port, pairing QR generation, active offer management, and paired device rename/revocation/deletion, all backed by the local runtime host.

## Non-Goals For This Version

Bootstrap installs and validates the runtime sidecar only. It does not install launchd, systemd, or Windows services; it does not persist identity-file paths; and it does not repair missing remote prerequisites beyond returning actionable failures.

Managed remote workspaces are created with `alera workspace add --host-id` or Desktop New Workspace after the sidecar is installed. Those flows fail with an actionable error when the host is missing, not bootstrapped, or unreachable. The local runtime host rewrites terminal launches for those workspaces to SSH and serves `workspace.files.list` / `workspace.files.read` over the same path. The Desktop explorer uses those verbs for a workspace whose `hostId` is not local.

The installed sidecar can run autonomously without the desktop app:

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

`runtime start` launches a persistent detached host for the selected runtime directory. `runtime stop` refuses active terminal sessions and host jobs unless `--force` is present. `runtime clear` deletes the selected runtime profile only while its host is stopped; `--force` first stops a live host and can recover when its control file is missing. Clear removes runtime databases, credentials, logs, retained terminal history, and runtime metadata without deleting repositories, project folders, or worktrees. This lifecycle is portable and intentionally does not install a system service. Mobile gateway, pairing, workspace state, terminals, enabled agent integrations, `spawnOnCreate` tabs, and coordinator-created workers continue to operate directly against that host. Pairing can be completed entirely from the CLI with `alera mobile --json pairing create`; the desktop pairing dialog is optional.
