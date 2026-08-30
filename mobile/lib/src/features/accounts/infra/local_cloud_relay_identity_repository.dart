import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/infra/local_cloud_account_repository.dart';

class LocalCloudRelayIdentityRepository
    implements VersionedCloudRelayIdentityRepository {
  LocalCloudRelayIdentityRepository({SecureValueStore? store})
    : _store = store ?? FlutterSecureValueStore();

  final SecureValueStore _store;

  @override
  Future<String> getOrCreatePrivateKey(String accountId) async =>
      (await getOrCreateIdentity(accountId)).privateKey;

  String _identityKey(String accountId) =>
      'alera.mobile.cloudRelayIdentity.v2.${base64UrlEncode(utf8.encode(accountId))}';

  @override
  Future<CloudRelayIdentity> getOrCreateIdentity(String accountId) async {
    final stored = await _store.read(_identityKey(accountId));
    if (stored != null) {
      try {
        final value = jsonDecode(stored) as Map<String, dynamic>;
        final key = value['privateKey'] as String;
        final version = value['keyVersion'] as int;
        if (version > 0 &&
            version <= 1000000 &&
            base64Url.decode(base64Url.normalize(key)).length == 32) {
          return CloudRelayIdentity(key, version);
        }
      } on Object {
        Logger(
          'RelayIdentity',
        ).warning('Stored relay identity is invalid; recovering registration.');
      }
    }
    final key =
        'alera.mobile.cloudRelayPrivateKey.v1.${base64UrlEncode(utf8.encode(accountId))}';
    final existing = await _store.read(key);
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        final decoded = base64Url.decode(base64Url.normalize(existing));
        if (decoded.length == 32) {
          return await _save(accountId, CloudRelayIdentity(existing.trim(), 1));
        }
      } on FormatException {
        Logger(
          'RelayIdentity',
        ).warning('Legacy relay identity is invalid; recovering registration.');
      }
    }
    return _save(accountId, CloudRelayIdentity(_newPrivateKey(), 1));
  }

  @override
  Future<CloudRelayIdentity> rotateIdentity(
    String accountId,
    CloudRelayIdentity previous,
  ) async {
    if (previous.keyVersion >= 1000000) {
      throw StateError('Relay identity rotation limit reached.');
    }
    return _save(
      accountId,
      CloudRelayIdentity(_newPrivateKey(), previous.keyVersion + 1),
    );
  }

  Future<CloudRelayIdentity> _save(
    String accountId,
    CloudRelayIdentity identity,
  ) async {
    await _store.write(
      _identityKey(accountId),
      jsonEncode({
        'privateKey': identity.privateKey,
        'keyVersion': identity.keyVersion,
      }),
    );
    return identity;
  }

  String _newPrivateKey() {
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
