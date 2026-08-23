import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_cloud_account_repository.dart';
import 'support/memory_host_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A paired host falls back to relay after a transport failure', () async {
    final unavailable = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = 'ws://${unavailable.address.address}:${unavailable.port}';
    await unavailable.close(force: true);
    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime-1',
        displayName: 'Alera Host',
        endpoint: endpoint,
        runtimeId: 'runtime-1',
        deviceId: 'device-1',
        pairedAt: DateTime.now().toUtc(),
      ),
      'token-1',
    );
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account-1',
        email: 'owner@example.com',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.now().toUtc().add(
        const Duration(hours: 1),
      ),
    );
    final relayApi = _FallbackRelayApi();
    final container = ProviderContainer(
      overrides: [
        hostRepositoryProvider.overrideWithValue(repository),
        cloudAccountRepositoryProvider.overrideWithValue(
          MemoryCloudAccountRepository(<CloudAccountSession>[session]),
        ),
        cloudRelayIdentityRepositoryProvider.overrideWithValue(
          _RelayIdentityRepository(),
        ),
        aleraRelayCloudApiProvider.overrideWithValue(relayApi),
      ],
    );
    addTearDown(container.dispose);
    final connection = container.listen(
      hostConnectionControllerProvider('runtime-1'),
      (_, _) {},
    );
    addTearDown(connection.close);

    await expectLater(
      container.read(hostConnectionControllerProvider('runtime-1').future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'relay fallback reached',
        ),
      ),
    );
    expect(relayApi.discoveryCalls, 1);
    expect(relayApi.registrationCalls, 1);
  });
}

class _RelayIdentityRepository implements CloudRelayIdentityRepository {
  @override
  Future<String> getOrCreatePrivateKey(String accountId) async =>
      base64UrlEncode(List<int>.filled(32, 7)).replaceAll('=', '');
}

class _FallbackRelayApi implements AleraRelayCloudApi {
  int discoveryCalls = 0;
  int registrationCalls = 0;

  @override
  Future<List<CloudRuntimeProfile>> discoverRuntimes(
    CloudAccountSession session,
  ) async {
    discoveryCalls += 1;
    return <CloudRuntimeProfile>[
      CloudRuntimeProfile(
        id: 'runtime-1',
        name: 'Alera Host',
        lastSeenAt: DateTime.now().toUtc(),
        relayPublicKey: base64UrlEncode(List<int>.filled(32, 8)),
        relayKeyVersion: 1,
      ),
    ];
  }

  @override
  Future<CloudRelayIdentityRegistration> registerRelayIdentity({
    required CloudAccountSession session,
    required String publicKey,
    required int keyVersion,
  }) {
    registrationCalls += 1;
    throw StateError('relay fallback reached');
  }

  @override
  Future<CloudRelayGrant> requestRelayGrant({
    required CloudAccountSession session,
    required String runtimeId,
  }) {
    throw UnimplementedError();
  }
}
