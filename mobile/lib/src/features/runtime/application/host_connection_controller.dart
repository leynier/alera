import 'dart:async';

import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_controller.g.dart';

/// Owns the WebSocket connection to one paired runtime host. The client is
/// connected and authenticated before it is exposed, and disposed together
/// with the provider so leaving the host screens tears the socket down.
@riverpod
class HostConnectionController extends _$HostConnectionController {
  @override
  Future<MobileRuntimeClient> build(String hostId) async {
    final hosts = await ref.watch(pairedHostsControllerProvider.future);
    final host = hosts.where((host) => host.id == hostId).firstOrNull;
    if (host == null) {
      throw StateError('Host Is Not Paired.');
    }
    final deviceToken = await ref
        .read(hostRepositoryProvider)
        .readDeviceToken(hostId);
    if (deviceToken == null || deviceToken.trim().isEmpty) {
      throw StateError('Device Token Is Missing.');
    }
    final client = await MobileRuntimeClient.connect(host.endpoint);
    try {
      await client.authenticate(
        deviceId: host.deviceId,
        deviceToken: deviceToken,
      );
    } on Object {
      await client.dispose();
      rethrow;
    }
    ref.onDispose(() {
      unawaited(client.dispose());
    });
    return client;
  }
}
