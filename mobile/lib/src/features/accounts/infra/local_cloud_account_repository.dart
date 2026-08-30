import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_repository.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureValueStore([FlutterSecureStorage? storage])
    implements SecureValueStore {
  this : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class LocalCloudAccountRepository({SecureValueStore? store})
    implements CloudAccountRepository {
  this : _store = store ?? FlutterSecureValueStore();

  static const String _sessionsKey = 'alera.mobile.cloudSessions.v1';
  static const String _installationIdKey =
      'alera.mobile.cloudInstallationId.v1';

  final SecureValueStore _store;

  @override
  Future<List<CloudAccountSession>> loadSessions() async {
    final encoded = await _store.read(_sessionsKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const <CloudAccountSession>[];
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        return const <CloudAccountSession>[];
      }
      return <CloudAccountSession>[
        for (final item in decoded)
          if (item is Map)
            CloudAccountSession.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
      ];
    } on FormatException {
      return const <CloudAccountSession>[];
    }
  }

  @override
  Future<void> saveSession(CloudAccountSession session) async {
    final current = await loadSessions();
    final next = <CloudAccountSession>[
      session,
      for (final existing in current)
        if (existing.account.id != session.account.id) existing,
    ];
    await _writeSessions(next);
  }

  @override
  Future<void> removeSession(String accountId) async {
    final current = await loadSessions();
    await _writeSessions(<CloudAccountSession>[
      for (final session in current)
        if (session.account.id != accountId) session,
    ]);
  }

  @override
  Future<String> getOrCreateInstallationId() async {
    final existing = await _store.read(_installationIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    final created = base64Url.encode(bytes).replaceAll('=', '');
    await _store.write(_installationIdKey, created);
    return created;
  }

  Future<void> _writeSessions(List<CloudAccountSession> sessions) {
    if (sessions.isEmpty) {
      return _store.delete(_sessionsKey);
    }
    return _store.write(
      _sessionsKey,
      jsonEncode(
        sessions.map((session) => session.toJson()).toList(growable: false),
      ),
    );
  }
}
