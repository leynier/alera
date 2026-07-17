import 'package:alera/src/app/app.dart';
import 'package:alera/src/features/app_window/infra/app_window_bootstrap.dart';
import 'package:alera/src/rust/frb_generated.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:alera/src/shared/infra/performance/performance_trace.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main(List<String> args) async {
  AleraPerformanceTrace.startStartup();
  WidgetsFlutterBinding.ensureInitialized();
  AleraPerformanceTrace.mark('widgets_initialized');
  await RustLib.init();
  AleraPerformanceTrace.mark('alera_rust_initialized');
  await code_forge.RustLib.init();
  AleraPerformanceTrace.mark('code_forge_rust_initialized');
  AppLogger.configure();
  final windowBootstrap = await bootstrapAppWindowBeforeRunApp();
  AleraPerformanceTrace.mark('window_bootstrapped');
  await initializeGhosttyVteWeb();
  AleraPerformanceTrace.mark('ghostty_initialized');
  AleraPerformanceTrace.recordFirstFrame();

  runApp(
    ProviderScope(
      overrides: [
        if (windowBootstrap.database case final db?)
          aleraDatabaseProvider.overrideWith((ref) {
            ref.onDispose(() async {
              await db.close();
            });
            return Future.value(db);
          }),
      ],
      child: const AleraApp(),
    ),
  );
  AleraPerformanceTrace.mark('run_app_called');
}
