import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class const AiDictationCredentialStatus({
  required final bool supported,
  required final bool configured,
  required final bool matchesBaseUrl,
});

abstract interface class AiDictationCredentialStore {
  Future<AiDictationCredentialStatus> status(String? baseUrl);

  Future<void> saveToken(String token, {required String baseUrl});

  Future<void> clearToken();
}

class RuntimeAiDictationCredentialStore(final RuntimeHostClient _client)
    implements AiDictationCredentialStore {
  @override
  Future<AiDictationCredentialStatus> status(String? baseUrl) async {
    if (_client case final RuntimeHostCapabilityClient capabilities) {
      final supported = await capabilities.supportsRuntimeCapability(
        aleraRuntimeHostRemoteAiDictationCapability,
      );
      if (!supported) {
        return const AiDictationCredentialStatus(
          supported: false,
          configured: false,
          matchesBaseUrl: false,
        );
      }
    }
    final response = await _client.runtimeRequest(
      'aiDictation.credentials.status',
      <String, Object?>{'baseUrl': baseUrl},
    );
    return AiDictationCredentialStatus(
      supported: true,
      configured: response is Map && response['configured'] == true,
      matchesBaseUrl: response is Map && response['matchesBaseUrl'] == true,
    );
  }

  @override
  Future<void> saveToken(String token, {required String baseUrl}) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty.');
    }
    await _client.runtimeRequest(
      'aiDictation.credentials.save',
      <String, Object?>{'token': normalized, 'baseUrl': baseUrl},
    );
  }

  @override
  Future<void> clearToken() async {
    await _client.runtimeRequest(
      'aiDictation.credentials.clear',
      const <String, Object?>{},
    );
  }
}
