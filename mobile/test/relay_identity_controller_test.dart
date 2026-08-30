import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/application/relay_identity_controller.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_cloud_account_repository.dart';

void main() {
  test('Concurrent connections share registration and recover a version conflict once', () async {
    final repository = _IdentityRepository();
    final api = _RelayApi();
    final session = CloudAccountSession(
      account: const CloudAccountProfile(
        id: 'account',
        email: 'a@example.test',
      ),
      accessToken: 'access',
      refreshToken: 'refresh',
      accessTokenExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final container = ProviderContainer(
      overrides: [
        cloudAccountRepositoryProvider.overrideWithValue(
          MemoryCloudAccountRepository([session]),
        ),
        cloudRelayIdentityRepositoryProvider.overrideWithValue(repository),
        aleraRelayCloudApiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(relayIdentityControllerProvider.notifier);
    final identities = await Future.wait(
      List.generate(8, (_) => controller.requireIdentity('account')),
    );
    expect(api.versions, [1, 2]);
    expect(repository.rotations, 1);
    expect(identities.every((key) => identical(key, identities.first)), isTrue);
    await controller.requireIdentity('account');
    expect(api.versions, [1, 2]);
  });
}

class _IdentityRepository implements VersionedCloudRelayIdentityRepository {
  CloudRelayIdentity value = CloudRelayIdentity(
    base64UrlEncode(.filled(32, 7)),
    1,
  );
  int rotations = 0;
  @override
  Future<String> getOrCreatePrivateKey(String accountId) async =>
      value.privateKey;
  @override
  Future<CloudRelayIdentity> getOrCreateIdentity(String accountId) async =>
      value;
  @override
  Future<CloudRelayIdentity> rotateIdentity(
    String accountId,
    CloudRelayIdentity previous,
  ) async {
    rotations++;
    return value = CloudRelayIdentity(
      base64UrlEncode(.filled(32, 8)),
      previous.keyVersion + 1,
    );
  }
}

class _RelayApi implements AleraRelayCloudApi {
  final versions = <int>[];
  @override
  Future<CloudRelayIdentityRegistration> registerRelayIdentity({
    required CloudAccountSession session,
    required String publicKey,
    required int keyVersion,
  }) async {
    versions.add(keyVersion);
    if (keyVersion == 1) {
      throw const AleraCloudException(
        'conflict',
        statusCode: 409,
        code: 'relay_key_rotation_conflict',
      );
    }
    return CloudRelayIdentityRegistration(
      clientId: 'cloud-installation-1',
      clientKind: 'mobile',
      publicKey: publicKey,
      keyVersion: keyVersion,
    );
  }

  @override
  Future<List<CloudRuntimeProfile>> discoverRuntimes(
    CloudAccountSession session,
  ) async => [];
  @override
  Future<CloudRelayGrant> requestRelayGrant({
    required CloudAccountSession session,
    required String runtimeId,
  }) => throw UnimplementedError();
}
