import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workbench_providers.g.dart';

/// The workspace surface of the host connection. Tests override this with a
/// fake so workbench controllers can run without a live gateway.
@riverpod
Future<MobileWorkspaceClient> workspaceClient(Ref ref, String hostId) {
  return ref.watch(hostConnectionControllerProvider(hostId).future);
}
