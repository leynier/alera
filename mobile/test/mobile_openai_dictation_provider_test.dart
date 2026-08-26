import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_credential_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_openai_dictation_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'stores direct token securely and binds it to provider origin',
    () async {
      final secureStore = _MemorySecureStore();
      final credentials = MobileAiDictationCredentialStore(store: secureStore);

      await credentials.saveToken(
        ' secret-token ',
        baseUrl: 'https://speech.example.test/v1',
      );

      expect(
        await credentials.tokenFor('https://speech.example.test/other'),
        'secret-token',
      );
      expect(
        () => credentials.tokenFor('https://other.example.test/v1'),
        throwsStateError,
      );
      expect(secureStore.values.values.single, contains('secret-token'));
    },
  );

  test('calls OpenAI-compatible transcription directly from mobile', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-mobile-openai-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final audio = File('${directory.path}/audio.wav');
    await audio.writeAsBytes(<int>[1, 2, 3]);
    final credentials = MobileAiDictationCredentialStore(
      store: _MemorySecureStore(),
    );
    await credentials.saveToken(
      'secret-token',
      baseUrl: 'https://speech.example.test/v1',
    );
    late http.Request captured;
    final provider = MobileOpenAiDictationProvider(
      credentials,
      clientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, String>{'text': ' hola '}),
          200,
        );
      }),
    );

    final result = await provider.transcribe(
      requestId: 'mobile-direct-1',
      audioPath: audio.path,
      baseUrl: 'https://speech.example.test/v1',
      model: 'speech-model',
      timeout: const Duration(seconds: 30),
      language: 'es',
    );

    expect(
      captured.url.toString(),
      'https://speech.example.test/v1/audio/transcriptions',
    );
    expect(captured.headers['authorization'], 'Bearer secret-token');
    expect(captured.body, contains('speech-model'));
    expect(captured.body, contains('name="file"'));
    expect(result.text, 'hola');
  });
}

class _MemorySecureStore implements MobileAiDictationSecureStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
