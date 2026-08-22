import 'dart:async';

import 'package:alera_mobile/src/app/alera_mobile_app.dart';
import 'package:alera_mobile/src/core/logging/global_error_handlers.dart';
import 'package:alera_mobile/src/core/logging/mobile_logger.dart';
import 'package:alera_mobile/src/features/diagnostics/application/diagnostics_settings.dart';
import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera_mobile/src/features/push_notifications/infra/mobile_firebase_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(_bootstrap, recordZoneError);
}

Future<void> _bootstrap() async {
  // The app used to start with no bootstrap at all, so nothing could be wired
  // before the first frame and no failure left a trace.
  WidgetsFlutterBinding.ensureInitialized();
  await MobileFirebaseBootstrap.initialize();
  await MobileLogger.configure();
  installGlobalErrorHandlers();

  final info = await PackageInfo.fromPlatform();
  CrashReporting.configureAppVersion(
    version: info.version,
    build: info.buildNumber,
  );
  final crashReportingEnabled = await readCrashReportingEnabled();

  await CrashReporting.run(
    enabled: crashReportingEnabled,
    release: 'alera-mobile@${info.version}+${info.buildNumber}',
    appRunner: () => runApp(const ProviderScope(child: AleraMobileApp())),
  );
}
