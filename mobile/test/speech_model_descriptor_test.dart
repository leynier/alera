import 'package:alera_mobile/src/features/ai_dictation/domain/speech_capabilities.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_model_descriptor.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_provider_profile.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips a multi-artifact streaming descriptor', () {
    final descriptor = SpeechModelDescriptor(
      id: 'zipformer-en',
      label: 'Streaming English',
      description: 'A streaming test model.',
      runtime: SpeechModelRuntime.sherpaOnnx,
      mode: SpeechRecognitionMode.streaming,
      artifacts: <SpeechModelArtifact>[
        SpeechModelArtifact(
          id: 'encoder',
          relativePath: 'encoder.onnx',
          uri: 'https://example.test/encoder.onnx',
          sha256: _repeat('a'),
          sizeBytes: 10,
        ),
        SpeechModelArtifact(
          id: 'tokens',
          relativePath: 'tokens.txt',
          uri: 'https://example.test/tokens.txt',
          sha256: _repeat('b'),
          sizeBytes: 2,
        ),
      ],
      languages: const <String>['en'],
      supportsAutomaticLanguageDetection: true,
      supportedProviders: const <SpeechExecutionProvider>{
        SpeechExecutionProvider.auto,
        SpeechExecutionProvider.cpu,
      },
      preferredProvider: SpeechExecutionProvider.auto,
    );

    final decoded = SpeechModelDescriptor.fromJson(descriptor.toJson());

    expect(decoded.id, descriptor.id);
    expect(decoded.runtime, SpeechModelRuntime.sherpaOnnx);
    expect(decoded.mode, SpeechRecognitionMode.streaming);
    expect(decoded.artifacts, hasLength(2));
    expect(decoded.preferredProvider, SpeechExecutionProvider.auto);
  });

  test('rejects an artifact path that escapes the model directory', () {
    expect(
      () => SpeechModelDescriptor(
        id: 'unsafe',
        label: 'Unsafe',
        description: 'Invalid descriptor.',
        runtime: SpeechModelRuntime.sherpaOnnx,
        mode: SpeechRecognitionMode.streaming,
        artifacts: <SpeechModelArtifact>[
          SpeechModelArtifact(
            id: 'encoder',
            relativePath: '../encoder.onnx',
            uri: 'https://example.test/encoder.onnx',
            sha256: _repeat('a'),
            sizeBytes: 1,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('normalizes provider endpoints with or without a v1 path', () {
    const profile = SpeechProviderProfile(
      id: 'office',
      label: 'Office STT',
      type: SpeechBackend.openAiCompatible,
      baseUrl: 'https://speech.example.test/v1/',
    );

    expect(
      profile.transcriptionUri().toString(),
      'https://speech.example.test/v1/audio/transcriptions',
    );
  });

  test('parses paired host capabilities without credentials', () {
    final capabilities = SpeechCapabilities.fromJson(<String, Object?>{
      'platform': 'macos',
      'backends': <Object?>[
        <String, Object?>{
          'location': 'pairedDevice',
          'backend': 'whisper',
          'batchFile': true,
          'guaranteedOnDevice': true,
          'models': <Object?>[
            <String, Object?>{
              'id': 'whisper-base',
              'label': 'Whisper Base',
              'installed': true,
            },
          ],
        },
      ],
    });

    expect(capabilities.platform, 'macos');
    expect(capabilities.supports(SpeechBackend.whisper), isTrue);
    expect(capabilities.backends.single.models.single.installed, isTrue);
  });

  test('keeps streaming and batch contracts separate', () {
    expect(StreamingSpeechSession, isNot(BatchSpeechTranscriber));
    expect(const SpeechPartialResult(text: 'hello').isFinal, isFalse);
    expect(
      const SpeechFinalResult(text: 'hello').executionProvider,
      SpeechExecutionProvider.cpu,
    );
  });
}

String _repeat(String value) => List<String>.filled(64, value).join();
