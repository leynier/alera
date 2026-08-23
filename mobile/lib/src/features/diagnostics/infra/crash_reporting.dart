import 'dart:async';

import 'package:alera_mobile/src/core/diagnostics/sentry_dsn.dart';
import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Opt-in crash reporting.
///
/// Reporting is off unless the user turns it on, and the switch is read inside
/// `beforeSend` rather than by tearing the client down, so flipping it takes
/// effect immediately without an app restart.
abstract final class CrashReporting {
  static const String _surface = 'mobile';
  static const String _versionsContextKey = 'alera_versions';

  static bool _enabled = false;
  static bool _initialized = false;
  static String _appVersion = 'unknown';
  static String _appBuild = 'unknown';
  static final Map<Object, _RuntimeVersionContext> _runtimeByConnection =
      <Object, _RuntimeVersionContext>{};

  static bool get isEnabled => _enabled;

  static void setEnabled(bool enabled) => _enabled = enabled;

  static void configureAppVersion({
    required String version,
    required String build,
  }) {
    _appVersion = _knownValue(version) ?? 'unknown';
    _appBuild = _knownValue(build) ?? 'unknown';
  }

  /// Records the version in the authenticated host's `status.get` response.
  ///
  /// A phone can keep more than one host connection alive. Distinct versions
  /// are therefore reported as `multiple` instead of attributing a generic app
  /// error to whichever connection happened to authenticate last.
  static void updateRuntimeContext(
    Object connection,
    Map<String, Object?> status,
  ) {
    final version = _knownValue(status['runtimeHostVersion']);
    if (version == null) {
      _runtimeByConnection.remove(connection);
      return;
    }
    _runtimeByConnection[connection] = _RuntimeVersionContext(
      version: version,
      build: _knownValue(status['runtimeHostCommit']),
      protocol: status['protocolVersion'] is int
          ? status['protocolVersion'] as int
          : null,
    );
  }

  static void clearRuntimeContext(Object connection) {
    _runtimeByConnection.remove(connection);
  }

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
    // Ordinary host reachability is connection state with retry UI, not a crash.
    if (_isReachabilityNoise(event)) {
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
    for (final breadcrumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
      final message = breadcrumb.message;
      if (message != null) {
        breadcrumb.message = redactLogText(message);
      }
    }
    return event;
  }

  static void _applyVersionContext(SentryEvent event) {
    final runtimes = _runtimeByConnection.values.toSet().toList()
      ..sort((left, right) => left.sortKey.compareTo(right.sortKey));
    final state = switch (runtimes.length) {
      0 => 'unavailable',
      1 => 'connected',
      _ => 'multiple',
    };
    final runtime = runtimes.length == 1 ? runtimes.single : null;
    final tags = event.tags ??= <String, String>{};
    tags['surface'] = _surface;
    tags['app_version'] = _appVersion;
    tags['app_build'] = _appBuild;
    tags['runtime_state'] = state;
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
      'runtime_state': state,
      if (runtime != null) 'runtime_version': runtime.version,
      'runtime_build': ?runtime?.build,
      'runtime_protocol': ?runtime?.protocol,
      if (runtimes.length > 1)
        'runtime_versions': <Map<String, Object?>>[
          for (final item in runtimes) item.toJson(),
        ],
    };
  }

  static bool _isReachabilityNoise(SentryEvent event) {
    final throwable = event.throwable;
    if (throwable != null && isHostReachabilityFailure(throwable)) {
      return true;
    }
    for (final exception in event.exceptions ?? const <SentryException>[]) {
      final nested = exception.throwable;
      if (nested != null && isHostReachabilityFailure(nested)) {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  static void applyOptionsForTesting(
    SentryFlutterOptions options,
    String release,
  ) => _applyOptions(options, release);

  static void _applyOptions(SentryFlutterOptions options, String release) {
    options.dsn = kAleraMobileSentryDsn;
    // The app handles repository paths, branch names and command lines; there
    // is no reason to attach IPs or request headers on top of that.
    options.sendDefaultPii = false;
    // Android 12+ retains a native tombstone after SIGABRT/SIGSEGV. Without
    // this, Sentry can receive only the signal and an unusable address list.
    options.enableTombstone = true;
    options.environment = kDebugMode ? 'dev' : 'release';
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
      await SentryFlutter.init((options) => _applyOptions(options, release));
    }
    await appRunner();
  }

  /// Test seam so a suite can exercise the filter without a live client.
  static void resetForTesting() {
    _enabled = false;
    _initialized = false;
    _appVersion = 'unknown';
    _appBuild = 'unknown';
    _runtimeByConnection.clear();
  }
}

String? _knownValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty || text == 'unknown' ? null : text;
}

final class _RuntimeVersionContext {
  const _RuntimeVersionContext({
    required this.version,
    required this.build,
    required this.protocol,
  });

  final String version;
  final String? build;
  final int? protocol;

  String get sortKey => '$version\u0000${build ?? ''}\u0000${protocol ?? ''}';

  Map<String, Object?> toJson() => <String, Object?>{
    'runtime_version': version,
    'runtime_build': ?build,
    'runtime_protocol': ?protocol,
  };

  @override
  bool operator ==(Object other) {
    return other is _RuntimeVersionContext &&
        other.version == version &&
        other.build == build &&
        other.protocol == protocol;
  }

  @override
  int get hashCode => Object.hash(version, build, protocol);
}
