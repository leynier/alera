import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/connection_attempt.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';

part 'relay_identity_controller.g.dart';

@Riverpod(keepAlive: true)
class RelayIdentityController extends _$RelayIdentityController {
  final Map<String, Future<RelayIdentityKeyPair>> _pending = {};
  final Map<String, (RelayIdentityKeyPair, DateTime)> _registered = {};

  @override
  void build() {
    ref.listen(cloudAccountsControllerProvider, (_, next) {
      if (!next.hasValue) return;
      final accounts = next.value!.map((item) => item.account.id).toSet();
      _registered.removeWhere((id, _) => !accounts.contains(id));
    });
  }

  Future<RelayIdentityKeyPair> requireIdentity(String accountId) async {
    final cached = _registered[accountId];
    if (cached != null &&
        DateTime.now().difference(cached.$2) < const Duration(seconds: 60)) {
      return cached.$1;
    }
    final current = _pending[accountId];
    if (current != null) return current;
    // A caller leaving one host must not cancel another host's registration.
    final scope = ConnectionAttempt();
    final operation = scope
        .run(() => _register(accountId))
        .whenComplete(scope.cancel);
    _pending[accountId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_pending[accountId], operation)) _pending.remove(accountId);
    }
  }

  Future<RelayIdentityKeyPair> _register(String accountId) async {
    final repository = ref.read(cloudRelayIdentityRepositoryProvider);
    var record = repository is VersionedCloudRelayIdentityRepository
        ? await repository.getOrCreateIdentity(accountId)
        : CloudRelayIdentity(
            await repository.getOrCreatePrivateKey(accountId),
            1,
          );
    final expectedId = await ref
        .read(cloudAccountRepositoryProvider)
        .getOrCreateInstallationId();
    for (var attempt = 0; attempt < 8; attempt++) {
      final key = await RelayIdentityKeyPair.fromPrivate(
        base64Url.decode(base64Url.normalize(record.privateKey)),
      );
      try {
        final registered = await ref
            .read(cloudAccountsControllerProvider.notifier)
            .withSession(
              accountId,
              (session) => ref
                  .read(aleraRelayCloudApiProvider)
                  .registerRelayIdentity(
                    session: session,
                    publicKey: base64UrlNoPadding(key.publicBytes),
                    keyVersion: record.keyVersion,
                  ),
            );
        if (registered.clientId != expectedId ||
            registered.clientKind != 'mobile' ||
            registered.publicKey != base64UrlNoPadding(key.publicBytes) ||
            registered.keyVersion != record.keyVersion) {
          throw const FormatException(
            'Cloud returned an invalid mobile identity',
          );
        }
        _registered[accountId] = (key, DateTime.now());
        return key;
      } on AleraCloudException catch (error) {
        if (error.code != 'relay_key_rotation_conflict' ||
            repository is! VersionedCloudRelayIdentityRepository ||
            attempt == 7) {
          rethrow;
        }
        record = await repository.rotateIdentity(accountId, record);
      }
    }
    throw StateError('Relay identity registration failed.');
  }
}
