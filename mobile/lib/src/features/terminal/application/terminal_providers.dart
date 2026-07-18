import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_providers.g.dart';

/// The terminal surface of the host connection. Tests override this with a
/// fake so tab and session controllers can run without a live gateway.
@riverpod
Future<MobileTerminalClient> terminalClient(Ref ref, String hostId) {
  return ref.watch(hostConnectionControllerProvider(hostId).future);
}
