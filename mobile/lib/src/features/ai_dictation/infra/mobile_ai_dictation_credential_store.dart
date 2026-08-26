import 'dart:convert';

import 'package:alera_mobile/src/core/logging/log_redaction.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_capabilities.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_provider_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _credentialKey = 'alera.mobile.aiDictation.openAiCompatible.v1';

class MobileAiDictationCredentialStatus {
  const MobileAiDictationCredentialStatus({
    required this.configured,
    required this.matchesBaseUrl,
  });

  final bool configured;
  final bool matchesBaseUrl;
}

abstract interface class MobileAiDictationSecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterMobileAiDictationSecureStore
    implements MobileAiDictationSecureStore {
  FlutterMobileAiDictationSecureStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MobileAiDictationCredentialStore {
  MobileAiDictationCredentialStore({MobileAiDictationSecureStore? store})
    : _store = store ?? FlutterMobileAiDictationSecureStore();

  final MobileAiDictationSecureStore _store;

  Future<MobileAiDictationCredentialStatus> status(String baseUrl) async {
    final credential = await _load();
    final origin = _profile(baseUrl).providerOrigin();
    return MobileAiDictationCredentialStatus(
      configured: credential != null,
      matchesBaseUrl: credential?.origin == origin,
    );
  }

  Future<void> saveToken(String token, {required String baseUrl}) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty.');
    }
    final origin = _profile(baseUrl).providerOrigin();
    registerLogSecret(normalized);
    await _store.write(
      _credentialKey,
      jsonEncode(<String, String>{'token': normalized, 'origin': origin}),
    );
  }

  Future<void> clearToken() => _store.delete(_credentialKey);

  Future<String?> tokenFor(String baseUrl) async {
    final credential = await _load();
    if (credential == null) return null;
    if (credential.origin != _profile(baseUrl).providerOrigin()) {
      throw StateError(
        'The saved AI Dictation token belongs to a different API origin.',
      );
    }
    return credential.token;
  }

  Future<_Credential?> _load() async {
    final value = await _store.read(_credentialKey);
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['token'] is! String ||
          decoded['origin'] is! String) {
        throw const FormatException();
      }
      final credential = _Credential(
        token: decoded['token'] as String,
        origin: decoded['origin'] as String,
      );
      registerLogSecret(credential.token);
      return credential;
    } on FormatException {
      throw StateError(
        'The saved AI Dictation token is invalid. Remove and save it again.',
      );
    }
  }

  SpeechProviderProfile _profile(String baseUrl) => SpeechProviderProfile(
    id: 'mobile-direct',
    label: 'OpenAI-Compatible API',
    type: SpeechBackend.openAiCompatible,
    baseUrl: baseUrl,
  );
}

class _Credential {
  const _Credential({required this.token, required this.origin});

  final String token;
  final String origin;
}
