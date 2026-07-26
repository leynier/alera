import 'dart:async';

import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_controller.g.dart';

/// The runtime socket ended without the app asking it to, so every stream and
/// pending request on that client is dead. Raised into the provider so screens
/// stop showing a live-looking connection and offer their Retry instead.
class RuntimeConnectionLost implements Exception {
  const RuntimeConnectionLost();

  @override
  String toString() => 'Lost The Connection To The Host';
}

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
    var ended = false;
    final closeSub = client.events.listen(
      (_) {},
      onError: (Object _, StackTrace _) => ended = true,
      onDone: () {
        if (ended) {
          return;
        }
        ended = true;
        // The plain AsyncError constructor, not copyWithPrevious: dependents
        // must stop seeing a value for a client that can no longer deliver.
        state = AsyncError(const RuntimeConnectionLost(), StackTrace.current);
      },
      cancelOnError: false,
    );
    ref.onDispose(closeSub.cancel);
    return client;
  }
}
