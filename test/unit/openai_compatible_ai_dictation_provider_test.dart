import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/infra/direct_ai_dictation_credential_store.dart';
import 'package:alera/src/features/ai_dictation/infra/openai_compatible_ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/infra/openai_compatible_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('builds standard and custom compatible transcription URLs', () {
    expect(
      openAiCompatibleTranscriptionUri(
        'https://api.openai.com',
        sendsToken: true,
      ).toString(),
      'https://api.openai.com/v1/audio/transcriptions',
    );
    expect(
      openAiCompatibleTranscriptionUri(
        'https://speech.example.test/custom/v2?tenant=one',
        sendsToken: false,
      ).toString(),
      'https://speech.example.test/custom/v2/audio/transcriptions?tenant=one',
    );
  });

  test('direct credentials are stored securely and bound to origin', () async {
    final storage = _MemorySecureStorage();
    final credentials = DirectAiDictationCredentialStore(storage: storage);

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
      throwsA(
        isA<AiDictationException>().having(
          (error) => error.kind,
          'kind',
          AiDictationErrorKind.invalidRequest,
        ),
      ),
    );
    expect(storage.values.values.single, isNot(contains('providerApiKey')));
  });

  test('transcribes directly with OpenAI-compatible multipart API', () async {
    final directory = await Directory.systemTemp.createTemp(
      'alera-direct-dictation-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final audio = File('${directory.path}/audio.wav');
    await audio.writeAsBytes(<int>[1, 2, 3, 4]);
    final credentials = DirectAiDictationCredentialStore(
      storage: _MemorySecureStorage(),
    );
    await credentials.saveToken(
      'secret-token',
      baseUrl: 'https://speech.example.test/v1',
    );
    late http.Request captured;
    final provider = OpenAiCompatibleAiDictationProvider(
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
      AiDictationRequest(
        requestId: 'direct-1',
        audioPath: audio.path,
        language: 'es',
        providerBaseUrl: 'https://speech.example.test/v1',
        providerModel: 'speech-model',
      ),
    );

    expect(
      captured.url.toString(),
      'https://speech.example.test/v1/audio/transcriptions',
    );
    expect(captured.headers['authorization'], 'Bearer secret-token');
    expect(captured.body, contains('speech-model'));
    expect(captured.body, contains('name="file"'));
    expect(result.text, 'hola');
    expect(result.providerId, 'openai-compatible-direct');
  });

  test('rejects bearer tokens over non-loopback cleartext', () {
    expect(
      () => openAiCompatibleTranscriptionUri(
        'http://speech.example.test/v1',
        sendsToken: true,
      ),
      throwsA(isA<AiDictationException>()),
    );
    expect(
      openAiCompatibleTranscriptionUri(
        'http://localhost:11434/v1',
        sendsToken: true,
      ).host,
      'localhost',
    );
  });
}

class _MemorySecureStorage implements AiDictationSecureStorage {
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
