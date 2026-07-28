---
name: alera-emulator
description: Use when inspecting, attaching, viewing, or automating Android emulators and iOS simulators through Alera, including screenshots, accessibility observations, gestures, typing, app installation and launch, Android permissions, and bounded logcat reads.
metadata:
  version: 1
---

# Alera Mobile Emulator

Use `alera emulator` to work with the single mobile-emulator tab associated with an Alera workspace. The runtime host owns device discovery, helper processes, input, observations, and lifecycle. Do not start `adb`, `emulator`, `simctl`, `scrcpy`, or `serve-sim` directly when this command surface is available.

## Check Capabilities First

```bash
alera emulator --json capabilities
```

Read the backend-specific capability flags before planning an operation. Android and iOS do not expose identical actions. An unsupported operation returns `unsupported_capability`; use a supported alternative or stop instead of retrying unchanged.

`--json` belongs to the command group, before the subcommand:

```bash
alera emulator --json devices --platform android
```

Replies deliberately omit private stream URLs and tokens. The embedded Alera tab consumes those credentials internally; agents do not need them.

## Resolve The Target

Commands that operate an attachment resolve their target in this order:

1. `--tab-id`
2. `--workspace-id`
3. `ALERA_WORKSPACE_ID`

`ALERA_TAB_ID` identifies the terminal running the command and is never treated as the emulator tab. Use `--tab-id` only with an emulator tab id returned by `list` or `attach`.

## Discover And Attach

```bash
alera emulator --json devices
alera emulator --json devices --platform ios
alera emulator --json attach --workspace-id <workspace-id> --platform android --device-id <avd-name>
alera emulator --json list --workspace-id <workspace-id>
```

Only virtual devices are supported. Android device ids are stable AVD names and iOS device ids are simulator UDIDs. An attachment persists the selected device on the workspace's emulator tab. If that device later becomes unavailable, Alera reports the error and does not silently switch to another device.

## Observe Then Act

```bash
alera emulator --json snapshot --workspace-id <workspace-id>
alera emulator --json tap --workspace-id <workspace-id> --snapshot-id <id> --x 0.25 --y 0.40
alera emulator --json gesture --workspace-id <workspace-id> --snapshot-id <id> --from-x 0.50 --from-y 0.80 --to-x 0.50 --to-y 0.25 --duration-ms 300
alera emulator --json type --workspace-id <workspace-id> --snapshot-id <id> --text "Hello"
alera emulator --json button --workspace-id <workspace-id> --snapshot-id <id> --button home
alera emulator --json rotate --workspace-id <workspace-id> --snapshot-id <id> --orientation landscape-left
```

Every action requires the exact `snapshotId` returned by a recent observation. Tap and gesture coordinates are normalized viewport positions from 0.0 through 1.0, independent of the current device resolution. Snapshot ids are short-lived and tied to the device, viewport, and orientation. After navigation, rotation, resizing, or any other state change, read a new snapshot instead of reusing coordinates from an old one. A stale-observation refusal protects against acting at the wrong location.

Use `--text-stdin` for sensitive text so it does not enter shell history:

```bash
alera emulator --json type --workspace-id <workspace-id> --snapshot-id <id> --text-stdin
```

## Application Development

Install and launch application builds:

```bash
alera emulator --json install --workspace-id <workspace-id> --path <apk-or-app-path>
alera emulator --json launch --workspace-id <workspace-id> --bundle-id <application-id>
alera emulator --json launch --workspace-id <workspace-id> --bundle-id <application-id> --activity <android-activity>
```

The package must match the attached backend: an APK for Android or a simulator-compatible `.app` for iOS. iOS device builds cannot run in the simulator.

Android also supports runtime permissions and bounded logcat reads:

```bash
alera emulator --json permission --workspace-id <workspace-id> --bundle-id <application-id> --permission android.permission.CAMERA --operation grant
alera emulator --json permission --workspace-id <workspace-id> --bundle-id <application-id> --permission android.permission.CAMERA --operation revoke
alera emulator --json logcat --workspace-id <workspace-id> --max-lines 200 --tag flutter --level warn
alera emulator --json logcat --workspace-id <workspace-id> --max-lines 100 --contains "FATAL EXCEPTION" --since 2026-07-27T12:00:00Z
```

`max-lines` is required to stay between 1 and 1000. Tags may be repeated. `permission` and `logcat` return `unsupported_capability` for iOS; do not translate them into unrelated simulator commands.

## Detach And Shutdown

```bash
alera emulator --json detach --workspace-id <workspace-id>
alera emulator --json shutdown --workspace-id <workspace-id>
```

`detach` releases the caller's stream lease without changing the selected device. `shutdown` powers off the virtual device only when Alera started it. A device that was already running before attachment remains running. Closing the permanent workspace tab follows the same ownership rule.

## Errors

Every application-level failure has `ok: false` and an error with `code`, `message`, and `nextSteps`. The CLI exits nonzero for these failures even though the runtime host answered successfully.

| Code | What to do |
|---|---|
| `unsupported_capability` | Read `capabilities` and use only operations enabled for the attached backend. |
| `device_not_found` | Run `devices` again and use an exact virtual-device id it reports. |
| `attachment_not_found` | Run `list`, then attach the workspace or pass the exact emulator tab id. |
| `device_unavailable` | Start or repair the selected virtual device; Alera will not choose a replacement. |
| `snapshot_stale` | Capture a fresh snapshot and use its id and coordinates. |
| `invalid_argument` | Fix the named flag or value. Do not repeat the command unchanged. |
| `operation_timeout` | Inspect `list` and the device state before deciding whether to retry. |
| `backend_unavailable` | Follow `nextSteps` to install or repair the platform SDK. |

## Boundaries

- Operate only the workspace and virtual device in scope.
- Treat application input as user-visible behavior. Do not submit purchases, messages, destructive forms, or account changes unless the user explicitly requested that action.
- Do not expose, copy, or reconstruct local stream transport credentials.
- Do not use these commands to drive physical phones or tablets.
