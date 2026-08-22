import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/accounts/application/cloud_relay_identity_repository.dart';
import 'package:alera_mobile/src/features/accounts/infra/local_cloud_account_repository.dart';

class LocalCloudRelayIdentityRepository
    implements CloudRelayIdentityRepository {
  LocalCloudRelayIdentityRepository({SecureValueStore? store})
    : _store = store ?? FlutterSecureValueStore();

  final SecureValueStore _store;

  @override
  Future<String> getOrCreatePrivateKey(String accountId) async {
    final key =
        'alera.mobile.cloudRelayPrivateKey.v1.${base64UrlEncode(utf8.encode(accountId))}';
    final existing = await _store.read(key);
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        final decoded = base64Url.decode(base64Url.normalize(existing));
        if (decoded.length == 32) {
          return existing.trim();
        }
      } on FormatException {
        // Replace a corrupt secure-store value with a fresh identity.
      }
    }
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final created = base64UrlEncode(bytes).replaceAll('=', '');
    await _store.write(key, created);
    return created;
  }
}
