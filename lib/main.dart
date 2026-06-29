import 'package:alera/src/app/app.dart';
import 'package:alera/src/features/app_window/infra/app_window_bootstrap.dart';
import 'package:alera/src/rust/frb_generated.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await code_forge.RustLib.init();
  AppLogger.configure();
  final windowBootstrap = await bootstrapAppWindowBeforeRunApp();
  await initializeGhosttyVteWeb();

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
}
