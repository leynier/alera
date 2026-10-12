# Mobile Access

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

Settings also includes a **Mobile Devices** section covering the full mobile companion lifecycle: gateway enable/bind host/port, pairing QR generation, active offer management, and paired device rename/revocation/deletion, all backed by the local runtime host.

A phone sees the remote hosts of its paired runtime through `mobile.hosts.list`, which names each host (id, alias, platform), its state, its runtime version and whether an update is available, and never how to reach it. See `docs/remote-hosts-hub.md`.
