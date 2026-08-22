import 'dart:async';

import 'package:alera_mobile/src/core/logging/mobile_logger.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Routes errors that never reach a `try`/`catch` into the log file.
///
/// Without these an uncaught error on a phone is invisible: there is no console
/// to read and the app had no crash reporting either.
void installGlobalErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    MobileLogger.recordError(
      details.exception,
      details.stack,
      context: 'FlutterError',
    );
    previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    MobileLogger.recordError(error, stack, context: 'PlatformDispatcher');
    return true;
  };
}

/// Records an error that escaped an async gap and reached the guarding zone.
void recordZoneError(Object error, StackTrace stack) {
  MobileLogger.recordError(error, stack, context: 'Zone');
  // Reachability failures already become connection state with retry UI; sending
  // them to Sentry just files noise like ALERA-MOBILE-APP-3.
  if (isHostReachabilityFailure(error)) {
    return;
  }
  unawaited(Sentry.captureException(error, stackTrace: stack));
}
