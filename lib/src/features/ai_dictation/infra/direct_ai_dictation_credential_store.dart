import 'dart:convert';

import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/infra/openai_compatible_endpoint.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_credential_store.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _credentialKey = 'ai_dictation.openai_compatible';

abstract interface class AiDictationSecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterAiDictationSecureStorage implements AiDictationSecureStorage {
  FlutterAiDictationSecureStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class DirectAiDictationCredentialStore implements AiDictationCredentialStore {
  DirectAiDictationCredentialStore({AiDictationSecureStorage? storage})
    : _storage = storage ?? FlutterAiDictationSecureStorage();

  final AiDictationSecureStorage _storage;

  @override
  Future<AiDictationCredentialStatus> status(String? baseUrl) async {
    final credential = await _load();
    final origin = _originOrNull(baseUrl);
    return AiDictationCredentialStatus(
      supported: true,
      configured: credential != null,
      matchesBaseUrl:
          credential != null && origin != null && credential.origin == origin,
    );
  }

  @override
  Future<void> saveToken(String token, {required String baseUrl}) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty.');
    }
    final origin = openAiCompatibleProviderOrigin(baseUrl);
    registerLogSecret(normalized);
    await _storage.write(
      _credentialKey,
      jsonEncode(<String, String>{'token': normalized, 'origin': origin}),
    );
  }

  @override
  Future<void> clearToken() => _storage.delete(_credentialKey);

  Future<String?> tokenFor(String baseUrl) async {
    final credential = await _load();
    if (credential == null) return null;
    final origin = openAiCompatibleProviderOrigin(baseUrl);
    if (credential.origin != origin) {
      throw const AiDictationException(
        AiDictationErrorKind.invalidRequest,
        'The saved AI Dictation token belongs to a different API origin. Replace or remove it before transcribing.',
      );
    }
    return credential.token;
  }

  Future<_DirectCredential?> _load() async {
    final value = await _storage.read(_credentialKey);
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['token'] is! String ||
          decoded['origin'] is! String) {
        throw const FormatException();
      }
      final credential = _DirectCredential(
        token: decoded['token'] as String,
        origin: decoded['origin'] as String,
      );
      registerLogSecret(credential.token);
      return credential;
    } on FormatException {
      throw const AiDictationException(
        AiDictationErrorKind.invalidRequest,
        'The saved AI Dictation credential is invalid. Remove and save it again.',
      );
    }
  }

  String? _originOrNull(String? baseUrl) {
    final value = baseUrl?.trim();
    if (value == null || value.isEmpty) return null;
    return openAiCompatibleProviderOrigin(value);
  }
}

class _DirectCredential {
  const _DirectCredential({required this.token, required this.origin});

  final String token;
  final String origin;
}
