import 'dart:async';

import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

/// Routes errors that never reach a `try`/`catch` into the log file.
///
/// Flutter's defaults print to the console and stop there, which a packaged
/// desktop build has no way to surface, so without this an uncaught error
/// leaves nothing behind to review afterwards.
void installGlobalErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.recordError(
      details.exception,
      details.stack,
      context: 'FlutterError',
    );
    _captureException(details.exception, details.stack);
    // Chain rather than replace so the console output and any test harness
    // expectations keep working.
    previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.recordError(error, stack, context: 'PlatformDispatcher');
    _captureException(error, stack);
    // Returning true marks the error handled; it is already recorded.
    return true;
  };
}

/// Records an error that escaped an async gap and reached the guarding zone.
///
/// `PlatformDispatcher.onError` covers most uncaught errors, but ones thrown
/// inside a zone-bound callback that never reaches the platform land here.
void recordZoneError(Object error, StackTrace stack) {
  AppLogger.recordError(error, stack, context: 'Zone');
  _captureException(error, stack);
}

void _captureException(Object error, StackTrace? stackTrace) {
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}
