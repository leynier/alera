# Remote Host Bootstrap

Alera can register SSH targets in the Home Runtime and install the standalone `alera` runtime sidecar on those hosts. This is the first remote-host path for mobile and agent-driven workflows: Projects, Workspaces, Tabs, SSH target state, and mobile access state remain runtime-owned, while a remote machine can receive a verified runtime binary over SSH.

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
alera ssh-target --json list
```

Add a target:

```bash
alera ssh-target --json add --alias build-mac --host mac.example.test --username leynier --auth agent
```

Preview a bootstrap:

```bash
alera ssh-target --json bootstrap-plan --id <target-id>
```

Start a bootstrap:

```bash
alera ssh-target --json bootstrap --id <target-id>
```

Cancel an active runtime-host bootstrap job:

```bash
alera ssh-target --json bootstrap-cancel --id <target-id>
```

When the runtime host is running, `bootstrap` starts a host job and returns immediately with a job id. Without a runtime host, the CLI performs the bootstrap in the foreground and prints progress to stderr.

## Mobile Access

Mobile companion pairing is managed from **Settings → Mobile Devices** in the desktop app: enable the gateway, tune bind host/port, generate a pairing offer rendered as a QR code (with a copy-JSON fallback), watch active offers with their expiry, and rename or revoke paired devices. The pane pre-validates custom endpoints with the same rules the runtime enforces and updates live through the `mobileSettingsChanged`, `mobilePairingsChanged`, `mobileDevicesChanged`, and `mobileGatewayChanged` events. The equivalent CLI surface remains available:

```bash
alera mobile --json enable --bind-host 127.0.0.1 --port 6768
alera mobile --json pairing create --endpoint wss://<host-or-vpn-name>:6768
alera mobile --json pairing cancel --id <pairing-id>
alera mobile --json devices list
alera mobile --json devices rename --id <device-id> --name <new-name>
alera mobile --json devices revoke --id <device-id>
alera mobile --json disable
```

The generated pairing payload can be pasted or scanned in the Flutter app under `mobile/`. The CLI starts or reuses a mobile-capable runtime host for enable and pairing creation so the WebSocket listener is live before a pairing payload is returned. The app opens the configured WebSocket endpoint, claims the pairing offer with `mobile.device.pair`, stores the returned device token in secure storage, then authenticates future sessions with `mobile.hello`. Runtimes advertising `mobileWorkspaceSidebarParityV1` expose a sidebar snapshot with projects, workspaces, tags, shared view preferences, shared activity, runtime settings, and agent presence. Those clients can also rename, pin, sleep, tag, link/unlink, create, and remove managed workspaces, open the repository URL on the phone, copy the host path, and create or attach to terminal sessions. Older runtimes are blocked from the parity workspace screen and must be updated instead of silently showing a reduced feature set. Mobile access defaults to a loopback bind. Plain `ws://` endpoints are accepted only for loopback/local development because pairing secrets and device tokens are bearer credentials; their explicit port must match the local gateway port. Phone/LAN/VPN access should expose the loopback gateway through a TLS tunnel or proxy and advertise `wss://`; the public TLS endpoint port can differ from the local gateway port. When intentionally binding `0.0.0.0`, pass a reachable `--endpoint` because the pairing payload cannot advertise a wildcard address. Device revocation, device rename, and pairing-offer cancellation are host-side operations (settings pane, CLI, or runtime-host RPCs `mobile.device.revoke`, `mobile.device.rename`, `mobile.pairing.cancel`); they are excluded from the mobile request allowlist, and revocation immediately disconnects active sessions for the revoked device. The pairing secret is returned only once at creation time, so the QR for an existing offer cannot be shown again - cancel it and generate a new one instead.

## Settings

Settings includes a **Remote Hosts** section for adding SSH targets, choosing optional platform/architecture/install directory overrides, previewing the bootstrap plan, starting bootstrap, and cancelling an active job. Bootstrap progress is delivered through runtime-host events and the persisted target status records the install directory, runtime version, platform, architecture, timestamps, and last redacted error.

Settings also includes a **Mobile Devices** section covering the full mobile companion lifecycle: gateway enable/bind host/port, pairing QR generation, active offer management, and paired device rename/revocation, all backed by the local runtime host.

## Non-Goals For This Version

Bootstrap installs and validates the runtime sidecar only. It does not install launchd, systemd, or Windows services; it does not persist identity-file paths; and it does not repair missing remote prerequisites beyond returning actionable failures.
