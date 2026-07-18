# Alera

Alera is the Android/iOS companion app for remote Alera work. It is a separate Flutter app so mobile plugins and platform manifests do not leak into the desktop app package.

## Current Surface

- Pair a host by pasting or scanning the JSON payload from `alera mobile --json pairing create`.
- Claim the pairing offer over the mobile WebSocket gateway and store the returned device token in platform secure storage.
- Authenticate with `mobile.hello`, show host status, projects, workspaces, and branch summaries, and start or attach to a terminal session with Flutter `xterm`.

## Local Commands

```bash
flutter pub get
flutter analyze
flutter test
```

Regenerate the native launcher icons and splash screens after changing files under `assets/branding/`:

```bash
dart run flutter_launcher_icons -f flutter_launcher_icons.yaml
dart run flutter_native_splash:create --path=flutter_native_splash.yaml
```

## Android Releases

Run the **Cut Mobile Release** GitHub Actions workflow to create an Android release. Mobile tags use `vX.Y.Z-mobile` for stable releases and `vX.Y.Z-rc.N-mobile` for release candidates, independently from desktop tags. Mobile release notes only include changes that touch `mobile/`, and mobile releases never take the repository's Latest badge (it stays on the desktop release). The workflow analyzes and tests the app, builds universal and architecture-specific APKs, verifies SHA-256 checksums, creates a draft GitHub Release, uploads and attests every artifact, and publishes only after the complete asset set passes verification. Use its `dry_run` input to preview the next version without creating commits, tags, or releases.

iOS publishing remains disabled until Apple signing and provisioning are configured; the generated iOS icon and splash resources continue to be maintained in the project.

Pairing payloads come from the runtime profile:

```bash
alera mobile --json enable --bind-host 127.0.0.1 --port 6768
alera mobile --json pairing create --endpoint ws://127.0.0.1:6768
```

The CLI starts or reuses a mobile-capable runtime host for enable and pairing creation so the gateway is accepting WebSocket connections before it returns a pairing payload. Mobile access defaults to a loopback bind. `ws://` pairing endpoints are accepted only for loopback/local development, and their explicit port must match the local gateway port. For phones over LAN/VPN, publish the loopback gateway through a TLS tunnel or proxy and create the pairing payload with an explicit `wss://<host-or-vpn-name>:<port>` endpoint; that public TLS port can differ from the local gateway port. When the gateway intentionally binds `0.0.0.0`, `pairing create` requires an explicit reachable `--endpoint` because phones cannot connect to a wildcard address. Mobile access is opt-in; use `alera mobile --json disable` to stop publishing the gateway and disconnect active mobile clients.

Run `alera mobile --json enable --port <port>` first when changing the local gateway port for loopback `ws://` pairing.

## Remaining Work

The first live transport includes status, projects, branches, workspaces, tabs, and terminal streaming. Agent status, file review, workspace creation/removal UX, and end-to-end encrypted payloads are intentionally left for later mobile iterations.
