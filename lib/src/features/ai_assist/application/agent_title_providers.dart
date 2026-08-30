import 'package:alera/src/features/ai_assist/application/agent_title_service.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_title_providers.g.dart';

@riverpod
AgentTitleService agentTitleService(Ref ref) =>
    AgentTitleService(ref.watch(runtimeHostClientProvider));

@riverpod
Future<bool> agentTitleAvailable(Ref ref) async {
  final enabled = ref.watch(
    settingsControllerProvider.select((s) => s.aiAssist.enabled),
  );
  if (!enabled) return false;
  final service = ref.watch(agentTitleServiceProvider);
  final subscription = service.client.runtimeEvents.listen((event) {
    if (event.name == 'runtimeSettingsChanged' ||
        event.name == aleraRuntimeHostConnectedEvent) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(subscription.cancel);
  try {
    return await service.isAvailable();
  } on Object {
    return false;
  }
}
