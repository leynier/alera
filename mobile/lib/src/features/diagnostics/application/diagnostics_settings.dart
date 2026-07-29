import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local key for the crash-reporting opt-in.
///
/// Stored on the phone rather than with the host's portable settings: it
/// governs what this device transmits, and it has to be readable at startup,
/// before any host connection exists.
const String kCrashReportingPreferenceKey = 'alera.mobile.crashReporting';

Future<bool> readCrashReportingEnabled() async {
  try {
    return await SharedPreferencesAsync().getBool(
          kCrashReportingPreferenceKey,
        ) ??
        false;
  } on Object {
    // A preferences failure must not stop the app from starting; staying off
    // is the safe answer when the stored choice cannot be read.
    return false;
  }
}

Future<void> writeCrashReportingEnabled(bool enabled) async {
  CrashReporting.setEnabled(enabled);
  try {
    await SharedPreferencesAsync().setBool(
      kCrashReportingPreferenceKey,
      enabled,
    );
  } on Object catch (error) {
    debugPrint('failed to persist the crash reporting preference: $error');
  }
}
