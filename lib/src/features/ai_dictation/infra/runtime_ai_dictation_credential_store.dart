import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

abstract interface class AiDictationCredentialStore {
  Future<bool> hasToken();

  Future<void> saveToken(String token);

  Future<void> clearToken();
}

class RuntimeAiDictationCredentialStore implements AiDictationCredentialStore {
  RuntimeAiDictationCredentialStore(this._client);

  final RuntimeHostClient _client;

  @override
  Future<bool> hasToken() async {
    final response = await _client.runtimeRequest(
      'aiDictation.credentials.status',
      const <String, Object?>{},
    );
    return response is Map && response['configured'] == true;
  }

  @override
  Future<void> saveToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty.');
    }
    await _client.runtimeRequest(
      'aiDictation.credentials.save',
      <String, Object?>{'token': normalized},
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
