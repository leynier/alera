import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_automation_providers.g.dart';

@riverpod
Future<List<MobileAutomation>> mobileAutomations(Ref ref, String hostId) async {
  final client = await watchHostConnection(ref, hostId);
  if (!client.supportsAutomations) {
    throw UnsupportedError('This host does not support automations');
  }
  return MobileRuntimeAutomationRepository(client).list();
}

@riverpod
Future<List<MobileAutomation>> mobileAutomationCatalog(
  Ref ref,
  String hostId,
  bool includeTrashed,
) async {
  final client = await watchHostConnection(ref, hostId);
  if (!client.supportsAutomations) {
    throw UnsupportedError('This host does not support automations');
  }
  return MobileRuntimeAutomationRepository(client)
      .list(includeTrashed: includeTrashed);
}
