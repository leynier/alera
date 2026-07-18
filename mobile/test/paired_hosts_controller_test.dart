import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  test('Saves and removes paired hosts through the controller', () async {
    final repository = MemoryHostRepository();
    final container = ProviderContainer(
      overrides: [hostRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      pairedHostsControllerProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);

    expect(await container.read(pairedHostsControllerProvider.future), isEmpty);

    await container
        .read(pairedHostsControllerProvider.notifier)
        .savePairedHost(_profile('runtime-1'), 'token-1');
    final hosts = await container.read(pairedHostsControllerProvider.future);
    expect(hosts.single.id, 'runtime-1');
    expect(await repository.readDeviceToken('runtime-1'), 'token-1');

    await container
        .read(pairedHostsControllerProvider.notifier)
        .removeHost('runtime-1');
    expect(await container.read(pairedHostsControllerProvider.future), isEmpty);
    expect(await repository.readDeviceToken('runtime-1'), isNull);
  });
}

PairedHostProfile _profile(String runtimeId) {
  return PairedHostProfile(
    id: runtimeId,
    displayName: 'Alera Host',
    endpoint: 'ws://127.0.0.1:6768',
    runtimeId: runtimeId,
    deviceId: 'device-1',
    pairedAt: DateTime.now().toUtc(),
  );
}
