import 'dart:collection';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/speech_model_descriptor.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'alera-mobile-dictation-model-',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('downloads, verifies, and removes a model', () async {
    const bytes = <int>[1, 2, 3, 4];
    final store = _store(supportDirectory, <http.StreamedResponse>[
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        HttpStatus.ok,
        contentLength: bytes.length,
      ),
    ], bytes);

    final path = await store.download('test-model');

    expect(await File(path).readAsBytes(), bytes);
    expect(await store.isInstalled('test-model'), isTrue);
    await store.remove('test-model');
    expect(await store.isInstalled('test-model'), isFalse);
  });

  test(
    'retains a partial transfer and resumes it with a range request',
    () async {
      const bytes = <int>[1, 2, 3, 4];
      final requests = <http.BaseRequest>[];
      final client = _QueuedClient(<http.StreamedResponse>[
        http.StreamedResponse(
          Stream<List<int>>.value(bytes.sublist(2)),
          HttpStatus.partialContent,
          contentLength: 2,
          headers: const <String, String>{
            HttpHeaders.contentRangeHeader: 'bytes 2-3/4',
          },
        ),
      ], requests);
      final store = _customStore(supportDirectory, client, bytes);
      final partial = File(await store.partialPath('test-model'));
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(bytes.sublist(0, 2));

      final path = await store.download('test-model');

      expect(await File(path).readAsBytes(), bytes);
      expect(requests.single.headers[HttpHeaders.rangeHeader], 'bytes=2-');
    },
  );

  test('rejects a model with the wrong checksum', () async {
    const expected = <int>[1, 2, 3, 4];
    const received = <int>[4, 3, 2, 1];
    final store = _store(supportDirectory, <http.StreamedResponse>[
      http.StreamedResponse(
        Stream<List<int>>.value(received),
        HttpStatus.ok,
        contentLength: received.length,
      ),
    ], expected);

    await expectLater(store.download('test-model'), throwsA(isA<StateError>()));
    expect(await store.isInstalled('test-model'), isFalse);
    expect(await File(await store.partialPath('test-model')).exists(), isFalse);
  });

  test('installs every artifact before publishing a multi-file model', () async {
    const encoder = <int>[1, 2];
    const decoder = <int>[3, 4, 5];
    final store = MobileAiDictationModelStore(
      clientFactory: () => _QueuedClient(<http.StreamedResponse>[
        http.StreamedResponse(
          Stream<List<int>>.value(encoder),
          HttpStatus.ok,
          contentLength: encoder.length,
        ),
        http.StreamedResponse(
          Stream<List<int>>.value(decoder),
          HttpStatus.ok,
          contentLength: decoder.length,
        ),
      ], <http.BaseRequest>[]),
      supportDirectory: () async => supportDirectory,
      catalog: <MobileAiDictationModel>[
        MobileAiDictationModel(
          id: 'streaming-model',
          label: 'Streaming Model',
          description: 'A synthetic multi-artifact model.',
          runtime: .sherpaOnnx,
          mode: .streaming,
          artifacts: <SpeechModelArtifact>[
            SpeechModelArtifact(
              id: 'encoder',
              relativePath: 'encoder.onnx',
              uri: 'https://example.test/encoder.onnx',
              sha256: sha256.convert(encoder).toString(),
              sizeBytes: encoder.length,
            ),
            SpeechModelArtifact(
              id: 'decoder',
              relativePath: 'decoder.onnx',
              uri: 'https://example.test/decoder.onnx',
              sha256: sha256.convert(decoder).toString(),
              sizeBytes: decoder.length,
            ),
          ],
        ),
      ],
    );

    final path = await store.download('streaming-model');

    expect(await File(path).readAsBytes(), encoder);
    expect(
      await File(
        await store.artifactPath(
          'streaming-model',
          store.modelFor('streaming-model').artifacts[1],
        ),
      ).readAsBytes(),
      decoder,
    );
    expect(await store.isInstalled('streaming-model'), isTrue);
    expect(
      await File(
        '${(await store.artifactPath('streaming-model', store.modelFor('streaming-model').artifacts[1]))}.part',
      ).exists(),
      isFalse,
    );
  });

  test(
    'does not publish a multi-file model when an artifact fails verification',
    () async {
      const first = <int>[1, 2];
      const second = <int>[9, 9];
      final store = MobileAiDictationModelStore(
        clientFactory: () => _QueuedClient(<http.StreamedResponse>[
          http.StreamedResponse(
            Stream<List<int>>.value(first),
            HttpStatus.ok,
            contentLength: first.length,
          ),
          http.StreamedResponse(
            Stream<List<int>>.value(second),
            HttpStatus.ok,
            contentLength: second.length,
          ),
        ], <http.BaseRequest>[]),
        supportDirectory: () async => supportDirectory,
        catalog: <MobileAiDictationModel>[
          MobileAiDictationModel(
            id: 'broken-model',
            label: 'Broken Model',
            description: 'A synthetic model with a bad checksum.',
            runtime: .sherpaOnnx,
            mode: .streaming,
            artifacts: <SpeechModelArtifact>[
              SpeechModelArtifact(
                id: 'encoder',
                relativePath: 'encoder.onnx',
                uri: 'https://example.test/encoder.onnx',
                sha256: sha256.convert(first).toString(),
                sizeBytes: first.length,
              ),
              SpeechModelArtifact(
                id: 'decoder',
                relativePath: 'decoder.onnx',
                uri: 'https://example.test/decoder.onnx',
                sha256: sha256.convert(<int>[3, 4]).toString(),
                sizeBytes: second.length,
              ),
            ],
          ),
        ],
      );

      await expectLater(
        store.download('broken-model'),
        throwsA(isA<StateError>()),
      );
      expect(await store.isInstalled('broken-model'), isFalse);
      expect(
        await File(await store.intentPath('broken-model')).exists(),
        isTrue,
      );
    },
  );
}

MobileAiDictationModelStore _store(
  Directory supportDirectory,
  List<http.StreamedResponse> responses,
  List<int> expected,
) => _customStore(
  supportDirectory,
  _QueuedClient(responses, <http.BaseRequest>[]),
  expected,
);

MobileAiDictationModelStore _customStore(
  Directory supportDirectory,
  http.Client client,
  List<int> expected,
) => MobileAiDictationModelStore(
  clientFactory: () => client,
  supportDirectory: () async => supportDirectory,
  catalog: <MobileAiDictationModel>[
    MobileAiDictationModel(
      id: 'test-model',
      label: 'Test Model',
      description: 'Test model.',
      fileName: 'model.bin',
      uri: 'https://example.test/model.bin',
      sha256: sha256.convert(expected).toString(),
      sizeBytes: expected.length,
    ),
  ],
);

final class _QueuedClient(
  Iterable<http.StreamedResponse> responses,
  final List<http.BaseRequest> requests,
) extends http.BaseClient {
  this : _responses = Queue<http.StreamedResponse>.of(responses);

  final Queue<http.StreamedResponse> _responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return _responses.removeFirst();
  }
}
