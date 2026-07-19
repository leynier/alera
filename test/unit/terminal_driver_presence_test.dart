import 'dart:typed_data';

import 'package:alera/src/features/workbench/application/terminal_driver_presence_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_host_test_fakes.dart';

const TerminalSessionDriver _phoneDriver = TerminalSessionDriver(
  kind: TerminalSessionDriverKind.mobile,
  deviceId: 'device-1',
  deviceName: 'Pixel',
);

FakeTerminalHostClient _fakeClient() {
  return FakeTerminalHostClient(
    attachment: TerminalHostAttachment(
      sessionId: 'session-1',
      created: true,
      running: true,
      snapshot: Uint8List(0),
    ),
  );
}

ProviderContainer _container(FakeTerminalHostClient client) {
  final container = ProviderContainer(
    overrides: [terminalHostClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('Bootstraps mobile-driven sessions from the driver list', () async {
    final client = _fakeClient()
      ..drivers = <String, TerminalSessionDriver>{
        'session-1': _phoneDriver,
        'session-2': const TerminalSessionDriver(
          kind: TerminalSessionDriverKind.desktop,
        ),
      };
    final container = _container(client);

    expect(container.read(terminalDriverPresenceControllerProvider), isEmpty);
    await Future<void>.delayed(Duration.zero);

    final drivers = container.read(terminalDriverPresenceControllerProvider);
    expect(drivers.keys, <String>['session-1']);
    expect(drivers['session-1']?.deviceName, 'Pixel');
  });

  test('Tracks driver-changed events and clears on desktop reclaim', () async {
    final client = _fakeClient();
    final container = _container(client);
    container.read(terminalDriverPresenceControllerProvider);

    client.emit(
      const TerminalHostDriverChangedEvent(
        'session-1',
        _phoneDriver,
        cols: 48,
        rows: 22,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(terminalDriverPresenceControllerProvider)['session-1'],
      isNotNull,
    );

    client.emit(
      const TerminalHostDriverChangedEvent(
        'session-1',
        TerminalSessionDriver(kind: TerminalSessionDriverKind.desktop),
        cols: 120,
        rows: 40,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(terminalDriverPresenceControllerProvider), isEmpty);
  });

  test('Reclaim and reclaim-all call through to the host client', () async {
    final client = _fakeClient();
    final container = _container(client);
    container.read(terminalDriverPresenceControllerProvider);
    client.emit(
      const TerminalHostDriverChangedEvent(
        'session-1',
        _phoneDriver,
        cols: 48,
        rows: 22,
      ),
    );
    client.emit(
      const TerminalHostDriverChangedEvent(
        'session-2',
        _phoneDriver,
        cols: 48,
        rows: 22,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(
      terminalDriverPresenceControllerProvider.notifier,
    );
    await controller.reclaim('session-1');
    expect(client.reclaimed, <String>['session-1']);

    await controller.reclaimAll();
    expect(client.reclaimed, containsAll(<String>['session-1', 'session-2']));
  });
}
