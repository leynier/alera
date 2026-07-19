# Alera

Alera is the Android/iOS companion app for remote Alera work. It is a separate Flutter app so mobile plugins and platform manifests do not leak into the desktop app package.

## Current Surface

- Pair a host with a QR-first flow: scan the pairing QR from the desktop pairing dialog (torch toggle included), or paste the JSON payload from `alera mobile --json pairing create` through the manual entry sheet. A confirmation step shows the host identity, endpoint, and a live offer-expiry countdown, plus an optional device name before pairing. Failures surface as titled states (Invalid Offer, Offer Expired, Runtime Mismatch, Could Not Reach Runtime) with retry and manual-entry actions.
- Claim the pairing offer over the mobile WebSocket gateway and store the returned device token in platform secure storage.
- Authenticate with `mobile.hello`, then land on a dense workspace list mirroring the desktop sidebar. Shared view preferences cover grouping, project/workspace sorting, project/tag and workspace-kind filters, section collapse, project collapse, parent-workspace collapse, and pins; desktop initializes the shared runtime record and wins revision conflicts, while mobile search stays transient. Pull to refresh, the visible search toolbar, Pinned and All sections, project grouping, and the parent/child tree use the same runtime snapshot.
- Use the visible three-dot menu or long-press a workspace to rename, pin/unpin, assign or create tags, configure or unlink the parent, open the repository in the phone browser, copy the host path, sleep the workspace, or remove a managed workspace. Removal follows the shared confirmation preference and only offers branch deletion for Alera-created branches, never reused branches. The New Workspace flow supports branch selection, source branch, existing-branch reuse, name, and parent workspace. The full parity surface requires `mobileWorkspaceSidebarParityV1`; older runtimes show an update-required state instead of a reduced workspace UI.
- Workspace rows show an aggregate agent count and highest urgency. Tapping a workspace opens its tabs screen, where each tab also shows its agent status for Codex, Claude, Copilot, Cursor, Antigravity, OpenCode, Pi, Amp, and Grok. Tabs remain horizontally scrollable with one tab visible at a time and no splits on the phone. The `+` button creates numbered terminal tabs, and chip delete closes a tab and terminates its session. The full-screen terminal uses the vendored Flutter `xterm` with JetBrains Mono, attaches with the measured viewport, and forwards resizes as the keyboard opens and closes.
- Terminal input has two modes per tab: compose (default), where you type a full command in a field and send it as one write (long-press Send offers sending without a newline), and direct, an opt-in toggle that streams every keystroke straight to the PTY. A configurable quick-key bar sits above the keyboard in both modes with Esc, Tab, Shift+Tab, arrows, and Ctrl combos; keys can be reordered, hidden, or extended with custom key combos (Ctrl/Alt/Shift plus any key) from the Terminal Quick Keys screen, persisted across launches.
- Opening a terminal claims its viewport (the mobile presence lock): the PTY resizes to the phone screen, the desktop pane shows a banner naming the driving device with Take Back actions, and desktop resizes are held for later instead of fighting the phone. When the desktop takes the terminal back the phone returns to the workspace list; detaching or losing the connection releases the claim and restores the desktop dims automatically. Feature-detected through the `terminalDriverPresence` runtime capability.
- Host status, projects, and branch summaries remain available under Host Details.

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

The CLI starts or reuses a mobile-capable runtime host for enable and pairing creation so the gateway is accepting WebSocket connections before it returns a pairing payload. Mobile access is opt-in; use `alera mobile --json disable` to stop publishing the gateway and disconnect active mobile clients.

## Remote Access Modes

The gateway has three endpoint modes, selectable from Settings > Mobile Devices in the desktop app (This Device / Tailscale / Manual) or persisted through the CLI:

- **This Device (default)**: loopback bind. `ws://` pairing endpoints are accepted only for loopback/local development, and their explicit port must match the local gateway port. Run `alera mobile --json enable --port <port>` first when changing the local gateway port for loopback `ws://` pairing.
- **Tailscale (recommended for remote access)**: run `alera mobile --json enable --tailscale` or pick the Tailscale mode in settings. The runtime verifies Tailscale is installed and running, binds the gateway to this machine's tailnet IPv4 (100.64.0.0/10), and emits pairing offers with `ws://<tailnet-ip>:<port>`. Plaintext `ws://` is acceptable here because traffic between tailnet devices rides Tailscale's WireGuard tunnel; the phone additionally refuses to store credentials when the pairing response's runtime id does not match the offer. The phone must have the Tailscale app installed and be signed in to the same tailnet. Tailscale is detected, never bundled: install it from https://tailscale.com/download on both devices.
- **Manual (advanced)**: publish the gateway yourself through a TLS tunnel or proxy and create the pairing payload with an explicit `wss://<host-or-vpn-name>:<port>` endpoint; that public TLS port can differ from the local gateway port. When the gateway intentionally binds `0.0.0.0`, `pairing create` requires an explicit reachable `--endpoint` because phones cannot connect to a wildcard address.

### Tailscale Troubleshooting

- `tailscale is not installed`: install Tailscale on the desktop, or use the Manual mode with a `wss://` endpoint.
- `tailscale is installed but not running`: run `tailscale up` and sign in, then retry.
- The phone cannot connect on Windows: allow Alera through Windows Firewall for incoming connections on the gateway port (the settings pane shows a hint when the Tailscale mode is active on Windows).
- The phone cannot connect anywhere: confirm the Tailscale app is connected on the phone, that both devices appear in the same tailnet, and that the tailnet's ACLs allow the connection.
- After removing the machine from the tailnet, the gateway may fail to bind its stale tailnet IP on restart; re-run `alera mobile --json enable --tailscale` or switch modes in settings to re-resolve.

## Remaining Work

The live transport includes host status, projects, branches, desktop-parity workspace organization and actions, agent status, tabs, and terminal streaming. File review, non-terminal tab surfaces, and end-to-end encrypted payloads are intentionally left for later mobile iterations.
