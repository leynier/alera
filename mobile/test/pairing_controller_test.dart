import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_flow_state.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_host_repository.dart';

void main() {
  test('Pairs and stores the host on the happy path', () async {
    final repository = MemoryHostRepository();
    final container = _container(
      repository,
      (offer, {deviceName}) async => const PairedDeviceCredentials(
        deviceId: 'device-1',
        displayName: 'My Phone',
        runtimeId: 'runtime-1',
        deviceToken: 'token-1',
      ),
    );

    final notifier = container.read(pairingControllerProvider.notifier);
    notifier.offerEntered(_rawOffer());
    expect(container.read(pairingControllerProvider), isA<PairingOfferReady>());

    await notifier.confirmPair(deviceName: 'My Phone');
    expect(container.read(pairingControllerProvider), isA<PairingSuccess>());
    final hosts = await repository.loadHosts();
    expect(hosts.single.runtimeId, 'runtime-1');
    expect(await repository.readDeviceToken('runtime-1'), 'token-1');
  });

  test('Reports expired offers distinctly', () {
    final container = _container(MemoryHostRepository(), _unusedPair);

    container
        .read(pairingControllerProvider.notifier)
        .offerEntered(
          _rawOffer(
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 1),
            ),
          ),
        );

    final state = container.read(pairingControllerProvider);
    expect(
      state,
      isA<PairingFailure>().having(
        (failure) => failure.reason,
        'reason',
        PairingFailureReason.offerExpired,
      ),
    );
  });

  test('Reports malformed offers as invalid', () {
    final container = _container(MemoryHostRepository(), _unusedPair);

    container
        .read(pairingControllerProvider.notifier)
        .offerEntered('not json at all');

    final state = container.read(pairingControllerProvider);
    expect(
      state,
      isA<PairingFailure>().having(
        (failure) => failure.reason,
        'reason',
        PairingFailureReason.invalidOffer,
      ),
    );
  });

  test('Reports a runtime mismatch from the pair response', () async {
    final repository = MemoryHostRepository();
    final container = _container(
      repository,
      (offer, {deviceName}) async => const PairedDeviceCredentials(
        deviceId: 'device-1',
        displayName: 'My Phone',
        runtimeId: 'runtime-other',
        deviceToken: 'token-1',
      ),
    );

    final notifier = container.read(pairingControllerProvider.notifier);
    notifier.offerEntered(_rawOffer());
    await notifier.confirmPair();

    final state = container.read(pairingControllerProvider);
    expect(
      state,
      isA<PairingFailure>().having(
        (failure) => failure.reason,
        'reason',
        PairingFailureReason.runtimeMismatch,
      ),
    );
    expect(await repository.loadHosts(), isEmpty);
  });

  test('Reports network failures as unreachable', () async {
    final container = _container(
      MemoryHostRepository(),
      (offer, {deviceName}) async =>
          throw const SocketException('Connection Refused'),
    );

    final notifier = container.read(pairingControllerProvider.notifier);
    notifier.offerEntered(_rawOffer());
    await notifier.confirmPair();

    final state = container.read(pairingControllerProvider);
    expect(
      state,
      isA<PairingFailure>().having(
        (failure) => failure.reason,
        'reason',
        PairingFailureReason.unreachable,
      ),
    );
  });
}

Future<PairedDeviceCredentials> _unusedPair(
  Object offer, {
  String? deviceName,
}) {
  throw StateError('Pairing Should Not Be Reached');
}

ProviderContainer _container(
  MemoryHostRepository repository,
  PairDeviceFunction pair,
) {
  final container = ProviderContainer(
    overrides: [
      hostRepositoryProvider.overrideWithValue(repository),
      pairDeviceFunctionProvider.overrideWithValue(pair),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(pairingControllerProvider, (_, _) {});
  addTearDown(subscription.close);
  return container;
}

String _rawOffer({DateTime? expiresAt}) {
  return jsonEncode(<String, Object?>{
    'v': aleraMobileProtocolVersion,
    'pairingId': 'pairing-1',
    'endpoint': 'ws://127.0.0.1:6768',
    'runtimeId': 'runtime-1',
    'hostName': 'Alera Host',
    'pairingSecret': 'secret-1',
    'expiresAt':
        (expiresAt ?? DateTime.now().toUtc().add(const Duration(minutes: 5)))
            .toIso8601String(),
  });
}
