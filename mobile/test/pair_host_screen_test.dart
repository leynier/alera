import 'dart:convert';

import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pair_host_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  testWidgets('Pairs a host through the manual entry path', (tester) async {
    final repository = MemoryHostRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostRepositoryProvider.overrideWithValue(repository),
          pairingScannerEnabledProvider.overrideWithValue(false),
          pairDeviceFunctionProvider.overrideWithValue(
            (offer, {deviceName}) async => const PairedDeviceCredentials(
              deviceId: 'device-1',
              displayName: 'My Phone',
              runtimeId: 'runtime-1',
              deviceToken: 'token-1',
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => const PairHostScreen(),
                      ),
                    );
                  },
                  child: const Text('Open Pairing'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Pairing'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter Code Manually'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      jsonEncode(<String, Object?>{
        'v': aleraMobileProtocolVersion,
        'pairingId': 'pairing-1',
        'endpoint': 'ws://127.0.0.1:6768',
        'runtimeId': 'runtime-1',
        'hostName': 'Alera Workstation',
        'pairingSecret': 'secret-1',
        'expiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      }),
    );
    await tester.pump();
    await tester.tap(find.text('Use This Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Alera Workstation'), findsOneWidget);
    expect(find.text('127.0.0.1:6768'), findsOneWidget);

    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();

    expect(find.text('Paired'), findsOneWidget);
    final hosts = await repository.loadHosts();
    expect(hosts.single.displayName, 'Alera Workstation');
    expect(await repository.readDeviceToken('runtime-1'), 'token-1');

    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Open Pairing'), findsOneWidget);
  });

  testWidgets('Shows a friendly failure for invalid offers', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hostRepositoryProvider.overrideWithValue(MemoryHostRepository()),
          pairingScannerEnabledProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: PairHostScreen()),
      ),
    );

    await tester.tap(find.text('Enter Code Manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    await tester.tap(find.text('Use This Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid Offer'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });
}
