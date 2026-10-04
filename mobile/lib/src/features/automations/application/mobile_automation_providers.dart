import 'package:alera_mobile/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_reader.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_providers.g.dart';

/// The paired runtime as the Automations screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.
@riverpod
Future<MobileAutomationClient> mobileAutomationClient(
  Ref ref,
  String hostId,
) async {
  final client = await watchHostConnection(ref, hostId);
  if (!client.supportsAutomations) {
    throw UnsupportedError('This host does not support automations');
  }
  return client;
}

@riverpod
Future<MobileRuntimeAutomationRepository> mobileAutomationRepository(
  Ref ref,
  String hostId,
) async => MobileRuntimeAutomationRepository(
  await ref.watch(mobileAutomationClientProvider(hostId).future),
);

/// The whole catalog of the host, trash included. Lifecycle events reload it;
/// the previous list stays visible while that happens.
@riverpod
class MobileAutomationCatalog extends _$MobileAutomationCatalog {
  @override
  Future<List<AutomationRecord>> build(String hostId) async {
    final repository = await ref.watch(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    final subscription = repository.events.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.list();
  }
}

@riverpod
class MobileAutomationDetail extends _$MobileAutomationDetail {
  @override
  Future<AutomationDetail> build(String hostId, String id) async {
    final repository = await ref.watch(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    final subscription = repository.events.listen((event) {
      final automationId = event.payload['automationId'];
      if (automationId is String && automationId != id) return;
      ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    return repository.show(id);
  }
}

@riverpod
class MobileAutomationRecentRuns extends _$MobileAutomationRecentRuns {
  @override
  Future<List<AutomationRunRecord>> build(String hostId) async {
    final repository = await ref.watch(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    final subscription = repository.events.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.recentRuns();
  }
}

class const MobileAutomationListState({
  final AutomationScope scope = AutomationScope.all,
  final AutomationCatalogFilters filters = const AutomationCatalogFilters(),
});

/// Scope and filters of the list, kept per host while the app runs.
@Riverpod(keepAlive: true)
class MobileAutomationListController extends _$MobileAutomationListController {
  @override
  MobileAutomationListState build(String hostId) =>
      const MobileAutomationListState();

  void setScope(AutomationScope scope) =>
      state = MobileAutomationListState(scope: scope, filters: state.filters);

  void setFilters(AutomationCatalogFilters filters) =>
      state = MobileAutomationListState(scope: state.scope, filters: filters);

  void clear() => state = const MobileAutomationListState();
}

/// Tabs this phone took over, so the terminal re-attaches normally at once.
@Riverpod(keepAlive: true)
class MobileAutomationTakenOverTabs extends _$MobileAutomationTakenOverTabs {
  @override
  Set<String> build(String hostId) => const <String>{};

  void mark(String tabId) => state = <String>{...state, tabId};
}

/// An automation-owned tab attaches read-only until somebody takes it over.
bool mobileAutomationTabIsObserved(
  Map<String, Object?> tabPayload,
  String tabId,
  Set<String> takenOverTabs,
) =>
    tabPayload['automationOwned'] == true &&
    tabPayload['automationTakenOver'] != true &&
    !takenOverTabs.contains(tabId);
