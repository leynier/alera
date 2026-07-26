import 'dart:async';

import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'host_connection_probe.g.dart';

/// Deliberately shorter than the client's own 20 s request timeout, which is
/// far too long to sit in front of a terminal that stopped updating.
const Duration _probeTimeout = Duration(seconds: 8);

/// Re-checks one host's socket when the app comes back to the foreground.
///
/// Mobile platforms suspend sockets in the background, and a NAT-idled
/// half-open TCP connection never surfaces an error on its own, so a client
/// that still looks live can be dead. One cheap round trip tells them apart.
@riverpod
class HostConnectionProbe extends _$HostConnectionProbe {
  @override
  void build(String hostId) {
    ref.listen(appLifecycleControllerProvider, (previous, next) {
      if (next != AppLifecycleState.resumed ||
          previous == AppLifecycleState.resumed) {
        return;
      }
      unawaited(_probe());
    });
  }

  Future<void> _probe() async {
    final connection = ref.read(hostConnectionControllerProvider(hostId));
    if (connection is AsyncError) {
      ref.invalidate(hostConnectionControllerProvider(hostId));
      return;
    }
    final client = connection.value;
    if (client == null) {
      return;
    }
    try {
      await client.mobileStatus().timeout(_probeTimeout);
    } on Object {
      ref.invalidate(hostConnectionControllerProvider(hostId));
    }
  }
}
