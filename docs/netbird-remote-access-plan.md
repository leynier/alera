# NetBird Remote Access Adoption Plan

## Scope and interpretation

This plan adds NetBird Cloud and self-hosted NetBird support to Alera's existing Mobile Gateway remote-access path. NetBird-based SSH target discovery is a separate feature and is not included here. A NetBird peer address can continue to be entered manually as an SSH target.

## Product specification

Alera will add **NetBird** beside **This Device**, **Tailscale**, and **Manual** in Settings > Mobile Devices.

The finished feature must let a desktop runtime with an active NetBird peer:

- bind the Mobile Gateway to its NetBird address;
- generate a pairing offer using `ws://<netbird-ip>:<port>`;
- pair and reconnect from an Android or iOS phone connected to the same NetBird network; and
- work with both NetBird Cloud and self-hosted management servers.

Alera will consume the active NetBird client profile. It will not install NetBird, sign the user in, select a profile, store setup keys, store management credentials, or provision NetBird peers and policies.

The user remains responsible for installing and configuring NetBird on both devices and allowing the gateway TCP port in NetBird policy. NetBird documents `netbird status --json` as parseable output and supports a custom management URL for self-hosted deployments:

- [NetBird CLI](https://docs.netbird.io/get-started/cli)
- [Bootstrap and parseable status](https://docs.netbird.io/manage/peers/bootstrap-via-config-file)
- [Android self-hosted management configuration](https://docs.netbird.io/get-started/install/android)
- [NetBird networks and WireGuard overlay](https://docs.netbird.io/manage/networks)

### Acceptance criteria

- NetBird mode reports missing, disconnected, and connected states.
- Connected status shows the active NetBird IP and whether the management URL is NetBird Cloud or self-hosted.
- Selecting NetBird resolves the current peer address and persists `endpointMode = netbird`.
- Pairing creation re-resolves the address and rebinds the gateway when necessary.
- Existing loopback, Tailscale, and manual TLS flows remain compatible.
- A runtime with an older sidecar fails safely with an update/restart hint instead of sending an unsupported mode.
- No Alera protocol version or mobile pairing version is bumped.

### Non-goals

- NetBird installation, login, setup-key handling, or management API calls.
- NetBird group, policy, route, DNS, or self-hosted server provisioning.
- Automatic peer discovery as SSH targets.
- Clientless phone access through a NetBird routing peer.
- Continuous monitoring of NetBird daemon changes after the gateway is already running.

## Technical design

### Runtime and persistence

Add `MobileEndpointMode::Netbird`, persisted as `netbird` in the existing `endpointMode` column. No database migration is expected because the column already stores endpoint mode strings.

Create `rust/alera-cli/src/netbird.rs`, following the process-safety and timeout pattern used by `tailscale.rs`:

- locate `netbird` through `PATH` and known Windows, macOS, and Linux installation paths;
- run `netbird status --json` through `windowless_async_command`;
- tolerate the NetBird IP being returned as either an address or CIDR;
- require a connected daemon, connected management service, and a usable peer IP;
- expose the active profile name and management URL; and
- redact credentials, query strings, and user information from displayed URLs and errors.

The status summary should contain `detected`, `connected`, `netbirdIp`, `profileName`, `managementUrl`, `managementKind`, and a redacted `error`. Treat `api.netbird.io` as `cloud`; classify another valid management host as `selfHosted`; otherwise use `unknown`.

When NetBird mode is selected or a pairing offer is generated, the runtime will read live status, resolve the current peer address, update `bindHost`, and rebind the gateway if the address changed. An address change caused by re-enrollment is handled when settings are applied or a new offer is created.

### Compatibility and capabilities

Advertise an additive `mobileNetBirdGatewayV1` capability in the runtime control file and `status.get`. The desktop may use the additive status object as a fallback signal when connected to a newer host without the capability gate.

Do not bump `PROTOCOL_VERSION`, `MOBILE_PROTOCOL_VERSION`, or the pairing payload version. The mobile app does not gain new runtime verbs and should not require a new mobile handshake capability for this feature.

### CLI

Add `--netbird` to `alera mobile --json enable`. Keep `--tailscale` for compatibility and make the two provider flags mutually exclusive.

`alera mobile --json status` will include the additive NetBird status object. Pairing creation without an explicit endpoint will use the resolved NetBird address.

### Desktop UI and endpoint validation

Extend the existing Mobile Gateway settings surface with a NetBird segment and a shared overlay-status row. The row should show:

- **Not Detected**;
- **Not Connected**;
- **Connected · <NetBird IP>**;
- the active NetBird profile; and
- **NetBird Cloud** or **Self-Hosted · <hostname>**.

Hide the manual endpoint field for both Tailscale and NetBird modes. Explain that both devices must join the same NetBird network and that its policy must allow TCP on the gateway port. Preserve the Windows Firewall hint.

Generalize endpoint validation copy from Tailscale-only wording to private-overlay wording. NetBird also uses the `100.64.0.0/10` private overlay range, so the mobile client should accept NetBird `ws://` offers while continuing to reject public plaintext endpoints. The existing application-level pairing secret, runtime identity pinning, and secure storage remain the trust boundaries.

### Mobile app

Do not add a NetBird SDK or credential flow to Alera Mobile. The user configures NetBird Cloud or the self-hosted management URL in the official NetBird app, then scans or pastes Alera's existing pairing offer.

Rename provider-specific endpoint tests and help copy where they describe a generic private overlay, while retaining Tailscale-specific tests for the existing provider.

## Implementation tasks

1. Extend the Rust runtime model, persistence handling, and round-trip tests with the `netbird` endpoint mode.
2. Implement the NetBird status adapter, tolerant parser, executable discovery, timeout handling, management URL classification, and redacted errors.
3. Wire NetBird resolution into mobile settings updates, pairing creation, gateway rebinding, CLI flags, status payloads, and runtime capabilities.
4. Extend desktop status models and repositories with old-payload tolerance.
5. Add the desktop selector, shared overlay status presentation, help copy, search keywords, and capability/update gating.
6. Generalize mobile pairing endpoint validation and add explicit NetBird fixtures and regression tests.
7. Update the mobile and remote-host documentation with Cloud, self-hosted, policy, firewall, and troubleshooting guidance.

## Validation plan

### Automated checks

- Rust fixtures for Cloud, self-hosted, disconnected, missing IP, invalid JSON, missing binary, timeout, IPv4/CIDR normalization, and URL redaction.
- Runtime-store round trips and CLI flag conflict tests.
- Gateway address resolution, rebind, and pairing generation tests.
- Desktop status parsing, selector, status-state, hidden-endpoint, and capability fallback widget tests.
- Mobile tests for NetBird overlay endpoints, public plaintext rejection, and runtime-id mismatch behavior.
- Existing loopback, Tailscale, manual TLS, and pairing regression suites.

### Manual matrix

- NetBird Cloud pairing and reconnect.
- Self-hosted NetBird pairing and reconnect.
- NetBird client discovery on Windows, macOS, and Linux.
- Android and iOS clients where signing permits.
- NetBird policy allowing versus denying the gateway TCP port.
- Gateway restart after a NetBird reconnect or address change.
- Windows Firewall behavior.
- Tailscale and NetBird both installed, documenting any operating-system route conflict caused by overlapping private overlay address space.

Run the repository Rust checks through `make rust-test`. Run Dart formatting, analysis, and tests for the desktop package and separately from `mobile/`. One-shot code generation is only needed if the implementation introduces generated Riverpod surfaces; no FRB regeneration is expected.

## Assumptions and risks

- The active NetBird profile is the source of truth for the runtime.
- Both devices are enrolled in the same NetBird account/network.
- Self-hosted management is reachable with valid TLS and is already configured in the NetBird clients.
- NetBird policies, not Alera, authorize the phone-to-runtime connection.
- NetBird and Tailscale may conflict when both are active because their private overlay address spaces overlap. Alera can select the requested provider's address but cannot control OS route selection on the phone.
