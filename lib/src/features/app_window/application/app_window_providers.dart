import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:alera/src/features/app_window/application/app_window_state_repository.dart';
import 'package:alera/src/features/app_window/infra/drift_app_window_state_repository.dart';
import 'package:alera/src/features/app_window/infra/platform_app_window_close_strategy.dart';
import 'package:alera/src/features/app_window/infra/screen_retriever_app_window_display_provider.dart';
import 'package:alera/src/features/app_window/infra/window_manager_app_window_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_window_providers.g.dart';

@Riverpod(keepAlive: true)
AppWindowStateRepository appWindowStateRepository(Ref ref) {
  final db = ref.watch(aleraDatabaseProvider).requireValue;
  return DriftAppWindowStateRepository(db);
}

@Riverpod(keepAlive: true)
AppWindowController appWindowController(Ref ref) {
  return WindowManagerAppWindowController();
}

@Riverpod(keepAlive: true)
AppWindowDisplayProvider appWindowDisplayProvider(Ref ref) {
  return ScreenRetrieverAppWindowDisplayProvider();
}

@Riverpod(keepAlive: true)
AppWindowLifecycleCoordinator appWindowLifecycleCoordinator(Ref ref) {
  final coordinator = AppWindowLifecycleCoordinator(
    repository: ref.watch(appWindowStateRepositoryProvider),
    window: ref.watch(appWindowControllerProvider),
    closeStrategy: PlatformAppWindowCloseStrategy(
      beforeLinuxExit: () async {
        ref.read(runtimeHostClientProvider).dispose();
      },
    ),
  );
  ref.onDispose(() {
    coordinator.stop();
  });
  return coordinator;
}
