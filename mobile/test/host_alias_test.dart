import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  group('PairedHostProfile alias', () {
    test('Round-trips through json and prefers the alias for display', () {
      final host = _profile().withAlias('Home Desk');
      final restored = PairedHostProfile.fromJson(host.toJson());

      expect(restored.alias, 'Home Desk');
      expect(restored.effectiveName, 'Home Desk');
      expect(restored.displayName, 'Alera Host');
    });

    test('Parses records stored before the alias existed', () {
      final json = _profile().toJson()..remove('alias');
      final restored = PairedHostProfile.fromJson(json);

      expect(restored.alias, isNull);
      expect(restored.effectiveName, 'Alera Host');
    });
  });

  test(
    'Controller updates and clears the alias without touching the token',
    () async {
      final repository = MemoryHostRepository();
      await repository.savePairedHost(_profile(), 'token-1');
      final container = ProviderContainer(
        overrides: [hostRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        pairedHostsControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      final notifier = container.read(pairedHostsControllerProvider.notifier);
      await notifier.updateHostAlias('runtime-1', 'Home Desk');
      var hosts = await container.read(pairedHostsControllerProvider.future);
      expect(hosts.single.effectiveName, 'Home Desk');
      expect(await repository.readDeviceToken('runtime-1'), 'token-1');

      await notifier.updateHostAlias('runtime-1', '   ');
      hosts = await container.read(pairedHostsControllerProvider.future);
      expect(hosts.single.alias, isNull);
      expect(hosts.single.effectiveName, 'Alera Host');
    },
  );

  testWidgets('Rename dialog pops with the entered name', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const AleraRenameDialog(
                      title: 'Rename Host',
                      labelText: 'Host Name',
                      initialValue: 'Alera Host',
                      allowEmpty: true,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Home Desk');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(result, 'Home Desk');

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
  });
}

PairedHostProfile _profile() {
  return PairedHostProfile(
    id: 'runtime-1',
    displayName: 'Alera Host',
    endpoint: 'ws://127.0.0.1:6768',
    runtimeId: 'runtime-1',
    deviceId: 'device-1',
    pairedAt: DateTime.now().toUtc(),
  );
}
