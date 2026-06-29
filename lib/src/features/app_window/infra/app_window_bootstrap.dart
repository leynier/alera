import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_platform.dart';
import 'package:alera/src/features/app_window/infra/drift_app_window_state_repository.dart';
import 'package:alera/src/features/app_window/infra/screen_retriever_app_window_display_provider.dart';
import 'package:alera/src/features/app_window/infra/window_manager_app_window_controller.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:logging/logging.dart';
import 'package:window_manager/window_manager.dart';

class AppWindowBootstrapResult {
  const AppWindowBootstrapResult({this.database});

  final AleraDatabase? database;
}

Future<AppWindowBootstrapResult> bootstrapAppWindowBeforeRunApp() async {
  if (!supportsDesktopAppWindowState) {
    return const AppWindowBootstrapResult();
  }
  await windowManager.ensureInitialized();
  final controller = WindowManagerAppWindowController();
  await controller.setTitle(kAleraAppName);

  AleraDatabase? db;
  try {
    db = await openAleraDb();
  } catch (error, stackTrace) {
    Logger('AppWindowBootstrap').warning(
      'failed to open database for app window restore',
      error,
      stackTrace,
    );
    return const AppWindowBootstrapResult();
  }

  try {
    await AppWindowRestorer(
      repository: DriftAppWindowStateRepository(db),
      window: controller,
      displays: ScreenRetrieverAppWindowDisplayProvider(),
    ).restore();
  } catch (error, stackTrace) {
    Logger(
      'AppWindowBootstrap',
    ).warning('failed to restore app window state', error, stackTrace);
  }
  return AppWindowBootstrapResult(database: db);
}
