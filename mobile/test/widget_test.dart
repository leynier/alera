import 'package:alera_mobile/src/app/alera_mobile_app.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  test('Pairing Result Uses Host Name For Stored Profile', () {
    final profile = PairedHostProfile.fromPairingResult(
      PairingOffer(
        version: aleraMobileProtocolVersion,
        pairingId: 'pairing',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        hostName: 'Alera Workstation',
        pairingSecret: 'secret',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
      const PairedDeviceCredentials(
        deviceId: 'device',
        displayName: 'Alera Mobile',
        runtimeId: 'runtime',
        deviceToken: 'token',
      ),
    );

    expect(profile.displayName, 'Alera Workstation');
  });

  testWidgets('Shows Stored Paired Host', (WidgetTester tester) async {
    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime',
        displayName: 'Alera Dev',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        deviceId: 'device',
        pairedAt: DateTime.now().toUtc(),
      ),
      'device-token',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [hostRepositoryProvider.overrideWithValue(repository)],
        child: const AleraMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alera Dev'), findsOneWidget);
    expect(await repository.readDeviceToken('runtime'), 'device-token');
  });
}
