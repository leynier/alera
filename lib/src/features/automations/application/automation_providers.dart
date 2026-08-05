import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAutomationRepository automationRepository(Ref ref) {
  return RuntimeAutomationRepository(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
Stream<List<AutomationRecord>> automationList(Ref ref) {
  return ref.watch(automationRepositoryProvider).watch();
}

@riverpod
Stream<List<AutomationRecord>> automationCatalog(
  Ref ref,
  bool includeTrashed,
) async* {
  final repository = ref.watch(automationRepositoryProvider);
  yield await repository.list(includeTrashed: includeTrashed);
  await for (final event in repository.watch()) {
    yield event;
  }
}
