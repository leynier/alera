import 'dart:async';

import 'package:alera/src/features/browser/application/browser_closed_tabs_service.dart';
import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/application/browser_history_service.dart';
import 'package:alera/src/features/browser/application/browser_native_callback_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_popup_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_permission_service.dart';
import 'package:alera/src/features/browser/application/browser_profile_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_profile_service.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/application/browser_settings_service.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/infra/browser_runtime_driver.dart';
import 'package:alera/src/features/browser/infra/plugin_browser_callback_bridge.dart';
import 'package:alera/src/features/browser/infra/plugin_browser_engine.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_closed_tabs_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_history_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_permission_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_profile_service.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_settings_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'browser_providers.g.dart';

@Riverpod(keepAlive: true)
BrowserNativeCallbackCoordinator browserNativeCallbackCoordinator(Ref ref) {
  return BrowserNativeCallbackCoordinator(
    fallbackPermission: (request, cancellation) async {
      final handle = ref
          .read(browserSessionRegistryProvider)
          .handleForPageId(request.pageId);
      if (handle == null || cancellation.isCancelled) {
        return BrowserPermissionDecision.deny;
      }
      final decision = await ref
          .read(browserPermissionServiceProvider)
          .decisionFor(
            profileId: handle.state.profileId,
            origin: request.origin,
            permission: request.permission,
          );
      return cancellation.isCancelled
          ? BrowserPermissionDecision.deny
          : decision;
    },
    fallbackPopup: (request, _) =>
        ref.read(browserPopupCoordinatorProvider).decide(request),
  );
}

@Riverpod(keepAlive: true)
AleraBrowserClient aleraBrowserClient(Ref ref) {
  final bridge = PluginBrowserCallbackBridge(
    coordinator: ref.watch(browserNativeCallbackCoordinatorProvider),
  );
  final client = AleraBrowserClient(callbacks: bridge.callbacks);
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
}

@Riverpod(keepAlive: true)
BrowserEngine browserEngine(Ref ref) {
  return PluginBrowserEngine(ref.watch(aleraBrowserClientProvider));
}

@Riverpod(keepAlive: true)
Future<BrowserEngineCapabilities> browserAvailability(Ref ref) {
  return ref.watch(browserEngineProvider).probeCapabilities();
}

@Riverpod(keepAlive: true)
BrowserSettingsService browserSettingsService(Ref ref) {
  return RuntimeBrowserSettingsService(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
BrowserProfileService browserProfileService(Ref ref) {
  return RuntimeBrowserProfileService(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
BrowserHistoryService browserHistoryService(Ref ref) {
  return RuntimeBrowserHistoryService(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
BrowserPermissionService browserPermissionService(Ref ref) {
  return RuntimeBrowserPermissionService(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
BrowserClosedTabsService browserClosedTabsService(Ref ref) {
  return RuntimeBrowserClosedTabsService(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
BrowserProfileCoordinator browserProfileCoordinator(Ref ref) {
  return BrowserProfileCoordinator(
    engine: ref.watch(browserEngineProvider),
    service: ref.watch(browserProfileServiceProvider),
  );
}

@Riverpod(keepAlive: true)
BrowserSessionRegistry browserSessionRegistry(Ref ref) {
  final registry = BrowserSessionRegistry(
    engine: ref.watch(browserEngineProvider),
    readSearchEngine: () async {
      try {
        return (await ref.read(browserSettingsServiceProvider).get())
            .searchEngine;
      } on Object {
        return BrowserSearchEngine.google;
      }
    },
  );
  ref.onDispose(() => unawaited(registry.dispose()));
  return registry;
}

@Riverpod(keepAlive: true)
BrowserPopupCoordinator browserPopupCoordinator(Ref ref) {
  final coordinator = BrowserPopupCoordinator(
    registry: ref.watch(browserSessionRegistryProvider),
    createWorkspaceTab:
        ({
          required String pageId,
          required String workspaceId,
          required String profileId,
          required String initialUrl,
        }) async {
          final state = ref.read(workbenchControllerProvider);
          final workspace = findWorkspaceById(state, workspaceId);
          if (workspace == null) {
            throw StateError('Workspace Not Found: $workspaceId');
          }
          return ref
              .read(workbenchControllerProvider.notifier)
              .createBrowserTab(
                workspace,
                pageId: pageId,
                profileId: profileId,
                initialUrl: initialUrl,
              );
        },
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
}

@Riverpod(keepAlive: true)
BrowserRuntimeDriver browserRuntimeDriver(Ref ref) {
  const uuid = Uuid();
  final registry = ref.watch(browserSessionRegistryProvider);
  final sessionReconciler = BrowserPersistentSessionReconciler(registry);
  final driver = BrowserRuntimeDriver(
    client: ref.watch(runtimeHostClientProvider),
    registry: registry,
    engine: ref.watch(browserEngineProvider),
    appInstanceId: uuid.v4(),
    driverInstanceId: uuid.v4(),
  );
  ref.listen(workbenchControllerProvider, (_, next) {
    if (!next.bootstrapped) {
      return;
    }
    final browserTabs = <WorkspaceTabRecord>[
      for (final tabs in next.tabsByWorkspace.values)
        for (final tab in tabs)
          if (tab.kind == WorkspaceTabKind.browser) tab,
    ];
    sessionReconciler.schedule(browserTabs);
  }, fireImmediately: true);
  unawaited(driver.start().catchError((Object _) {}));
  ref.onDispose(() {
    sessionReconciler.dispose();
    unawaited(driver.dispose());
  });
  return driver;
}

@Riverpod(keepAlive: true)
BrowserRuntimeDriver browserEventDispatcher(Ref ref) {
  return ref.watch(browserRuntimeDriverProvider);
}
