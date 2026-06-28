# Remote Host Bootstrap

Alera can register SSH targets in the Home Runtime and install the standalone `alera` runtime sidecar on those hosts. This is the first remote-host path for future mobile and agent-driven workflows: Projects, Workspaces, Tabs, and SSH target state remain runtime-owned, while a remote machine can receive a verified runtime binary over SSH.

## Supported Targets

Bootstrap supports `x64` and `arm64` macOS, Linux, and Windows hosts reachable through the local OpenSSH tools. Authentication is intentionally limited to SSH agent or key configuration in `~/.ssh/config`; password bootstrap is rejected. Platform and architecture can be saved on the target or overridden per bootstrap, otherwise Alera probes the remote host.

Default install directories are:

- macOS/Linux: `~/.alera/runtime`
- Windows: `%LOCALAPPDATA%\Alera\runtime`

The install directory can be overridden from Settings or the CLI.

## Artifact Trust

Release bootstrap uses a signed runtime archive from GitHub Releases. The archive lists each `alera-runtime-<version>-<platform>-<arch>.tar.gz` artifact with SHA-256 and size metadata, and the archive itself is signed with the same Ed25519 manifest key used by desktop update indexes. A release build passes that public key to the runtime host sidecar through `ALERA_RUNTIME_ARCHIVE_PUBLIC_KEY`.

Local development can pass `--artifact-path` to install a local tarball. That path is marked as a local override and is not treated as a signed release artifact.

## CLI

List targets:

```bash
alera ssh-target list --json
```

Add a target:

```bash
alera ssh-target add --alias build-mac --host mac.example.test --username leynier --auth agent --json
```

Preview a bootstrap:

```bash
alera ssh-target bootstrap-plan --id <target-id> --json
```

Start a bootstrap:

```bash
alera ssh-target bootstrap --id <target-id> --json
```

Cancel an active runtime-host bootstrap job:

```bash
alera ssh-target bootstrap-cancel --id <target-id> --json
```

When the runtime host is running, `bootstrap` starts a host job and returns immediately with a job id. Without a runtime host, the CLI performs the bootstrap in the foreground and prints progress to stderr.

## Settings

Settings includes a **Remote Hosts** section for adding SSH targets, choosing optional platform/architecture/install directory overrides, previewing the bootstrap plan, starting bootstrap, and cancelling an active job. Bootstrap progress is delivered through runtime-host events and the persisted target status records the install directory, runtime version, platform, architecture, timestamps, and last redacted error.

## Non-Goals For This Version

Bootstrap installs and validates the runtime sidecar only. It does not install launchd, systemd, or Windows services; it does not persist identity-file paths; and it does not repair missing remote prerequisites beyond returning actionable failures.
