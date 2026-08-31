import 'dart:async';

import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/core/diagnostics/sentry_dsn.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:sentry/sentry.dart';

/// Opt-in crash reporting.
///
/// Reporting is off unless the user turns it on, and the switch is read inside
/// `beforeSend` rather than by tearing the client down, so flipping it takes
/// effect immediately without an app restart.
///
/// Uses the pure-Dart SDK rather than `sentry_flutter`, whose Linux plugin
/// forces the crashpad backend and so requires libcurl built with AsynchDNS.
/// That would make libcurl a build and runtime dependency of Alera on Linux for
/// every user, in exchange for native crash capture the app barely needs: Dart
/// errors are already covered by the global handlers, and the crashes worth
/// catching natively happen in the Rust sidecar, which reports them itself.
abstract final class CrashReporting {
  static const String _surface = 'desktop';
  static const String _versionsContextKey = 'alera_versions';

  static bool _enabled = false;
  static bool _initialized = false;
  static String _appVersion = 'unknown';
  static String _appBuild = 'unknown';
  static _RuntimeVersionContext? _runtime;

  static bool get isEnabled => _enabled;

  static void setEnabled(bool enabled) => _enabled = enabled;

  static void configureAppVersion({
    required String version,
    required String build,
  }) {
    _appVersion = _knownValue(version) ?? 'unknown';
    _appBuild = _knownValue(build) ?? 'unknown';
  }

  /// Records the version reported by the host that answered `status.get`.
  ///
  /// The bundled sidecar is deliberately not used as a fallback: a persistent
  /// host may outlive an app update, so only the live reply identifies the code
  /// that actually served an operation.
  static void updateRuntimeContext(Map<String, Object?> status) {
    final version = _knownValue(status['runtimeHostVersion']);
    if (version == null) {
      _runtime = null;
      return;
    }
    _runtime = _RuntimeVersionContext(
      version: version,
      build: _knownValue(status['runtimeHostCommit']),
      protocol: status['protocolVersion'] is int
          ? status['protocolVersion'] as int
          : null,
    );
  }

  static void clearRuntimeContext() => _runtime = null;

  /// Masks every text-bearing field of an event, then drops it entirely when
  /// reporting is off.
  ///
  /// The log file is already redacted, but a Sentry event is built from the raw
  /// throwable, so skipping this would send a secret to a third party that was
  /// deliberately kept out of the local file.
  static SentryEvent? filterEvent(SentryEvent event) {
    if (!_enabled) {
      return null;
    }
    // Host shutdown is expected when stopped from the status bar, by idle
    // sidecar shutdown, or while the app exits; keep it local, not a crash.
    // A request timeout is deliberately excluded: its stable legacy message
    // mentions closure, but a slow request is not evidence of a dead socket.
    if (event.throwable is TerminalHostConnectionClosedException ||
        event.exceptions?.any(
              (exception) =>
                  exception.throwable is TerminalHostConnectionClosedException,
            ) ==
            true) {
      return null;
    }
    _applyVersionContext(event);
    final message = event.message;
    if (message != null) {
      event.message = SentryMessage(
        redactLogText(message.formatted),
        template: message.template,
        params: message.params,
      );
    }
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      final value = exception.value;
      if (value != null) {
        exception.value = redactLogText(value);
      }
    }
    for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
      final crumbMessage = crumb.message;
      if (crumbMessage != null) {
        crumb.message = redactLogText(crumbMessage);
      }
    }
    return event;
  }

  static void _applyVersionContext(SentryEvent event) {
    final runtime = _runtime;
    final tags = event.tags ??= <String, String>{};
    tags['surface'] = _surface;
    tags['app_version'] = _appVersion;
    tags['app_build'] = _appBuild;
    tags['runtime_state'] = runtime == null ? 'unavailable' : 'connected';
    if (runtime != null) {
      tags['runtime_version'] = runtime.version;
      if (runtime.build case final build?) {
        tags['runtime_build'] = build;
      }
      if (runtime.protocol case final protocol?) {
        tags['runtime_protocol'] = protocol.toString();
      }
    }
    event.contexts[_versionsContextKey] = <String, Object?>{
      'surface': _surface,
      'app_version': _appVersion,
      'app_build': _appBuild,
      'runtime_state': runtime == null ? 'unavailable' : 'connected',
      if (runtime != null) 'runtime_version': runtime.version,
      'runtime_build': ?runtime?.build,
      'runtime_protocol': ?runtime?.protocol,
    };
  }

  static void _applyOptions(SentryOptions options, String release) {
    options.dsn = kAleraDesktopSentryDsn;
    // The app handles repository paths, branch names and command lines; there
    // is no reason to attach IPs or request headers on top of that.
    options.sendDefaultPii = false;
    options.environment = kAleraFlavor;
    options.release = release;
    options.dist = _appBuild == 'unknown' ? null : _appBuild;
    options.beforeSend = (event, hint) async => filterEvent(event);
  }

  /// Starts Sentry and then runs [appRunner] in the caller's zone.
  ///
  /// Initialization happens regardless of the setting so the switch can be
  /// flipped later without a restart; nothing is transmitted while it is off.
  static Future<void> run({
    required bool enabled,
    required String release,
    required FutureOr<void> Function() appRunner,
  }) async {
    setEnabled(enabled);
    if (!_initialized) {
      _initialized = true;
      await Sentry.init((options) => _applyOptions(options, release));
    }
    await appRunner();
  }

  /// Test seam so a suite can exercise the filter without a live client.
  static void resetForTesting() {
    _enabled = false;
    _initialized = false;
    _appVersion = 'unknown';
    _appBuild = 'unknown';
    _runtime = null;
  }
}

String? _knownValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'unknown' ? null : text;
}

final class const _RuntimeVersionContext({
  required final String version,
  required final String? build,
  required final int? protocol,
});
