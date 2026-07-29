import 'dart:async';

import 'package:alera_mobile/src/core/diagnostics/sentry_dsn.dart';
import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Opt-in crash reporting.
///
/// Reporting is off unless the user turns it on, and the switch is read inside
/// `beforeSend` rather than by tearing the client down, so flipping it takes
/// effect immediately without an app restart.
abstract final class CrashReporting {
  static bool _enabled = false;
  static bool _initialized = false;

  static bool get isEnabled => _enabled;

  static void setEnabled(bool enabled) => _enabled = enabled;

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
    final message = event.message;
    return event.copyWith(
      message: message == null
          ? null
          : SentryMessage(
              redactLogText(message.formatted),
              template: message.template,
              params: message.params,
            ),
      exceptions: event.exceptions
          ?.map(
            (exception) => exception.copyWith(
              value: exception.value == null
                  ? null
                  : redactLogText(exception.value!),
            ),
          )
          .toList(),
      breadcrumbs: event.breadcrumbs
          ?.map(
            (crumb) => crumb.copyWith(
              message: crumb.message == null
                  ? null
                  : redactLogText(crumb.message!),
            ),
          )
          .toList(),
    );
  }

  static void _applyOptions(SentryFlutterOptions options, String release) {
    options.dsn = kAleraMobileSentryDsn;
    // The app handles repository paths, branch names and command lines; there
    // is no reason to attach IPs or request headers on top of that.
    options.sendDefaultPii = false;
    options.environment = kDebugMode ? 'dev' : 'release';
    options.release = release;
    options.beforeSend = (event, hint) async => filterEvent(event);
  }

  /// Starts Sentry and runs [appRunner] inside it.
  ///
  /// Initialization happens regardless of the setting so the switch can be
  /// flipped later without a restart; nothing is transmitted while it is off.
  static Future<void> run({
    required bool enabled,
    required String release,
    required FutureOr<void> Function() appRunner,
  }) async {
    setEnabled(enabled);
    if (_initialized) {
      await appRunner();
      return;
    }
    _initialized = true;
    await SentryFlutter.init(
      (options) => _applyOptions(options, release),
      appRunner: () async => appRunner(),
    );
  }

  /// Test seam so a suite can exercise the filter without a live client.
  static void resetForTesting() {
    _enabled = false;
    _initialized = false;
  }
}
