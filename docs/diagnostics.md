# Diagnostics

Alera writes rotating log files on the machine so an error can be reviewed after it happened. Logging is always on; sending anything off the machine is opt-in and off by default.

## Where Logs Live

| Surface | Directory | Base name |
|---|---|---|
| Runtime host | `<runtimeDir>/logs/` | `runtime.log` |
| Desktop app | `<applicationSupport>/logs/` | `alera.log` |
| Mobile app | `<applicationSupport>/logs/` | `alera-mobile.log` |

`<runtimeDir>` is the runtime profile directory: `<applicationSupport>/terminal_host` for an app-launched sidecar, and `ALERA_RUNTIME_DIR` or `~/.alera/runtime` for a CLI-started one. A remote runtime writes to its own machine; collect those over SSH.

The runtime reports its directory through `status.get` as `logDirectory`, guarded by the additive `hostDiagnosticsLogsV1` capability, so the desktop never has to re-derive the path. A host that does not advertise it simply contributes no runtime logs.

## Format And Rotation

One JSON object per line: `ts` (ISO 8601 UTC), `level`, `source` (`app`, `runtime` or `mobile`), `logger`, `msg`, and optional `error` and `stack`. JSON Lines rather than free text because the diagnostics bundle merges app and runtime logs into a single timeline.

Rotation is by size, not by date, so the disk cost stays predictable whether the host runs quietly for a week or crash-loops: `alera.log`, `alera.1.log`, and so on. Desktop and runtime keep 5 files of 5 MB; mobile keeps 3 of 2 MB, because phone storage is scarcer and a companion app writes far less.

## Redaction

Secrets are masked in the sink, not at the call sites, so a new log line cannot forget to do it. Two mechanisms:

- Pattern matching for `token=`, `secret=`, `password=`, `apiKey=`, `authorization=`, `deviceToken=` and `Bearer <value>`.
- Literal registration: the desktop registers the runtime host token when it launches the sidecar, the sidecar registers its own control token, and mobile registers its device token. This catches a secret logged with no recognizable key beside it.

The same redaction runs on Sentry events, because those are built from the raw throwable rather than from the log line.

## Reviewing An Error

**Desktop**: Settings → Application → Diagnostics.

- **Open Logs Folder** reveals the app log directory.
- **Export Diagnostics** saves a zip with `app/*.log`, `runtime/*.log` and a `meta.json` recording app version and flavor, platform, and the runtime host version, commit, protocol version and capabilities. This is the file worth attaching to a report; `meta.json` marks the runtime as unreachable when the sidecar was down, which is itself a useful signal.
- **Log Level** controls detail on both the app and the runtime; the level is sent to the sidecar in `configure`.

**Mobile**: Settings → Diagnostics → Export Logs shares the files through the system share sheet. Mobile logs stay on the phone and are never uploaded to the runtime: a phone worth diagnosing is usually one that cannot reach its host.

**Runtime, in the foreground**: `make host-debug` still prints everything to stderr. The file sink and the stderr layer coexist, and stderr is only attached when a terminal is present.

`ALERA_HOST_LOG` overrides the sidecar's level (`ALERA_HOST_LOG=debug`), following the `ALERA_HOST_*` convention of the makefile's other debug knobs.

## Crash Reporting

Off by default on both apps and on the sidecar. When enabled, crashes go to Sentry, one project per surface (`alera-runtime`, `alera-desktop-app`, `alera-mobile-app`) because the three version independently and a shared project would make release tracking and issue grouping meaningless.

The DSNs are committed in `lib/src/core/diagnostics/sentry_dsn.dart`, its mobile counterpart, and `sentry_reporting.rs`. A DSN is not a secret: it is designed to travel inside the client and ends up in the distributed binary regardless.

The desktop uses the **pure-Dart `sentry` package, not `sentry_flutter`**. The latter's Linux plugin forces the crashpad backend, which requires libcurl built with `AsynchDNS`; that would make libcurl a build and runtime dependency of Alera on Linux for every user, in exchange for native crash capture this app barely needs. Dart errors are already covered by the global handlers, and the crashes worth catching natively happen in the Rust sidecar, which reports them itself. Mobile keeps `sentry_flutter`, where the platform SDKs carry no such constraint.

`sendDefaultPii` is off everywhere. The desktop and the sidecar handle repository paths, branch names and command lines; there is no reason to attach IPs or request headers on top of that.

The switch is read inside `beforeSend` rather than by tearing the client down, so turning it off takes effect immediately, including for a sidecar that is already running: the desktop sends `crashReporting` on every `configure`. The build flavor becomes the Sentry `environment`, so dev noise can be filtered out; the app passes `ALERA_FLAVOR` to the sidecar, which cannot otherwise know which flavor launched it.

## Panics And Uncaught Errors

The sidecar installs a panic hook that writes the message, location and backtrace to its log before the process dies. This matters because the sidecar is spawned detached with its stderr pointed at null: before this, a panic in the actor loop left no trace at all beyond a runtime that stopped answering. The hook is installed **before** `sentry::init`, whose panic integration chains the previous hook, so a panic reaches the local file even when reporting is disabled or its upload fails.

Both Flutter apps install `FlutterError.onError`, `PlatformDispatcher.instance.onError` and a guarding zone, and the desktop adds a Riverpod `ProviderObserver` so a failing provider is recorded rather than only rendered as an `AsyncError`.

## Rules For Contributors

- New diagnostics in the sidecar use `tracing::warn!`/`error!`/`info!`, never `eprintln!`. The `println!`/`eprintln!` calls in `main.rs` and the `*_commands.rs` files are user-facing command output, which is a different thing and stays as it is.
- Never log a secret and rely on it being harmless. Register the literal with `register_secret` / `registerLogSecret` at the point it is created.
- Log-file and crash-report changes are additive: they MUST NOT bump `aleraTerminalHostProtocolVersion`, because a version mismatch makes the app treat a live host as unusable.
- Logging must never be the reason the app fails to start. Every sink failure degrades to no file rather than throwing.
