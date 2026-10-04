import 'dart:async';

import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAutomationRepository automationRepository(Ref ref) {
  return RuntimeAutomationRepository(ref.watch(runtimeHostClientProvider));
}

/// The whole catalog of the connected runtime, trash included, so scope,
/// bucket and filter changes never wait on the network. Every lifecycle event
/// and every runtime reconnection reloads it; Riverpod keeps the previous
/// list visible while that happens.
@Riverpod(keepAlive: true)
class AutomationCatalog extends _$AutomationCatalog {
  @override
  Future<List<AutomationRecord>> build() async {
    final repository = ref.watch(automationRepositoryProvider);
    final subscription = repository.events.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.list();
  }
}

@riverpod
class AutomationDetailController extends _$AutomationDetailController {
  @override
  Future<AutomationDetail> build(String id) async {
    final repository = ref.watch(automationRepositoryProvider);
    final subscription = repository.events.listen((event) {
      final automationId = event.payload['automationId'];
      if (automationId is String && automationId != id) return;
      ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    return repository.show(id);
  }
}

/// Recent runs across every automation, for the workspace scope's "Runs In
/// This Workspace" list. Run ownership never creates a scheduling association.
@riverpod
class AutomationRecentRuns extends _$AutomationRecentRuns {
  @override
  Future<List<AutomationRunRecord>> build() async {
    final repository = ref.watch(automationRepositoryProvider);
    final subscription = repository.events.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.recentRuns();
  }
}

class const AutomationCapabilities({
  final bool authoring = false,
  final bool observe = false,
});

@Riverpod(keepAlive: true)
class AutomationRuntimeCapabilities extends _$AutomationRuntimeCapabilities {
  @override
  Future<AutomationCapabilities> build() async {
    final repository = ref.watch(automationRepositoryProvider);
    final subscription = repository.events.listen((event) {
      if (event.name == 'runtimeHostConnected') ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    final results = await Future.wait(<Future<bool>>[
      repository.supports(automationsAuthoringCapability),
      repository.supports(automationTerminalObserveCapability),
    ]);
    return AutomationCapabilities(authoring: results[0], observe: results[1]);
  }
}

/// Tag ids to names, refreshed with the catalog.
@riverpod
Future<Map<String, String>> automationTagNames(Ref ref) async {
  ref.watch(automationCatalogProvider);
  final tags = await ref.watch(automationRepositoryProvider).tags();
  return <String, String>{
    for (final tag in tags)
      if (tag['id'] is String)
        tag['id']! as String: '${tag['name'] ?? tag['id']}',
  };
}
