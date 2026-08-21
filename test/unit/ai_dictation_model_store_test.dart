import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late List<int> bytes;
  late AiDictationModel model;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('alera-model-store-');
    bytes = <int>[1, 2, 3, 4];
    model = AiDictationModel(
      id: 'fixture',
      label: 'Fixture',
      description: 'Test model.',
      fileName: 'fixture.bin',
      sha256: sha256.convert(bytes).toString(),
      uri: 'https://example.test/fixture.bin',
      sizeBytes: bytes.length,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('downloads and atomically installs a verified model', () async {
    final store = _store(
      directory,
      model,
      (_) async => http.Response.bytes(bytes, HttpStatus.ok),
    );

    final path = await store.download(id: model.id);

    expect(await File(path).readAsBytes(), bytes);
    expect(await store.isInstalled(model.id), isTrue);
    expect(await store.resumeIntentIds(), isEmpty);
  });

  test('installs the matching Core ML encoder beside the model', () async {
    final encoderBytes = _coreMlArchive('fixture-encoder.mlmodelc');
    final acceleratedModel = _withCoreMlEncoder(model, encoderBytes);
    final progress = <double>[];
    final store = AiDictationModelStore(
      clientFactory: () => MockClient((request) async {
        if (request.url.toString() == acceleratedModel.uri) {
          return http.Response.bytes(bytes, HttpStatus.ok);
        }
        return http.Response.bytes(encoderBytes, HttpStatus.ok);
      }),
      supportDirectory: () async => directory,
      modelCatalog: <AiDictationModel>[acceleratedModel],
      installCoreMlEncoder: true,
    );

    final path = await store.download(
      id: acceleratedModel.id,
      onProgress: progress.add,
    );

    final encoder = Directory(
      '${File(path).parent.path}${Platform.pathSeparator}fixture-encoder.mlmodelc',
    );
    expect(await File('${encoder.path}/model.mil').readAsBytes(), bytes);
    expect(await store.isInstalled(acceleratedModel.id), isTrue);
    expect(progress.last, 1);
  });

  test(
    'adds Core ML to an existing model without downloading it again',
    () async {
      final encoderBytes = _coreMlArchive('fixture-encoder.mlmodelc');
      final acceleratedModel = _withCoreMlEncoder(model, encoderBytes);
      final requested = <Uri>[];
      final store = AiDictationModelStore(
        clientFactory: () => MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(encoderBytes, HttpStatus.ok);
        }),
        supportDirectory: () async => directory,
        modelCatalog: <AiDictationModel>[acceleratedModel],
        installCoreMlEncoder: true,
      );
      final path = await store.modelPath(acceleratedModel.id);
      await File(path).create(recursive: true);
      await File(path).writeAsBytes(bytes);
      await File('$path.sha256').writeAsString(acceleratedModel.sha256);

      expect(await store.partialBytes(acceleratedModel.id), bytes.length);
      await store.download(id: acceleratedModel.id);

      expect(requested, <Uri>[
        Uri.parse(acceleratedModel.coreMlEncoder!.archiveUri),
      ]);
      expect(await store.isInstalled(acceleratedModel.id), isTrue);
    },
  );

  test('resumes a partial model with a validated range response', () async {
    late String? range;
    final store = _store(directory, model, (request) async {
      range = request.headers[HttpHeaders.rangeHeader];
      return http.Response.bytes(
        bytes.sublist(2),
        HttpStatus.partialContent,
        headers: <String, String>{
          HttpHeaders.contentRangeHeader: 'bytes 2-3/4',
        },
      );
    });
    await File(await store.partialPath(model.id))
        .create(recursive: true)
        .then((file) => file.writeAsBytes(bytes.sublist(0, 2)));

    final path = await store.download(id: model.id);

    expect(range, 'bytes=2-');
    expect(await File(path).readAsBytes(), bytes);
  });

  test('restarts safely when a server ignores the range header', () async {
    final store = _store(
      directory,
      model,
      (_) async => http.Response.bytes(bytes, HttpStatus.ok),
    );
    await File(await store.partialPath(model.id))
        .create(recursive: true)
        .then((file) => file.writeAsBytes(bytes.sublist(0, 2)));

    final path = await store.download(id: model.id);

    expect(await File(path).readAsBytes(), bytes);
  });

  test('retains a failed download for a later resume', () async {
    final invalid = AiDictationModel(
      id: model.id,
      label: model.label,
      description: model.description,
      fileName: model.fileName,
      sha256: 'invalid',
      uri: model.uri,
      sizeBytes: model.sizeBytes,
    );
    final store = _store(
      directory,
      invalid,
      (_) async => http.Response.bytes(bytes, HttpStatus.ok),
    );

    await expectLater(
      store.download(id: invalid.id),
      throwsA(isA<StateError>()),
    );

    expect(await store.partialBytes(invalid.id), bytes.length);
    expect(await store.resumeIntentIds(), <String>[invalid.id]);
  });

  test(
    'explicit cancellation deletes partial data and resume intent',
    () async {
      final client = _HangingClient();
      final store = AiDictationModelStore(
        clientFactory: () => client,
        supportDirectory: () async => directory,
        modelCatalog: <AiDictationModel>[model],
      );
      final download = store.download(id: model.id);
      final cancellation = expectLater(
        download,
        throwsA(isA<AiDictationDownloadCancelled>()),
      );
      await client.started.future;

      await store.cancelDownload(model.id);

      await cancellation;
      expect(await store.partialBytes(model.id), 0);
      expect(await store.resumeIntentIds(), isEmpty);
    },
  );
}

AiDictationModelStore _store(
  Directory directory,
  AiDictationModel model,
  Future<http.Response> Function(http.Request request) handler,
) => AiDictationModelStore(
  clientFactory: () => MockClient(handler),
  supportDirectory: () async => directory,
  modelCatalog: <AiDictationModel>[model],
  installCoreMlEncoder: false,
);

AiDictationModel _withCoreMlEncoder(
  AiDictationModel model,
  List<int> archiveBytes,
) => AiDictationModel(
  id: model.id,
  label: model.label,
  description: model.description,
  fileName: model.fileName,
  sha256: model.sha256,
  uri: model.uri,
  sizeBytes: model.sizeBytes,
  coreMlEncoder: AiDictationCoreMlEncoder(
    directoryName: 'fixture-encoder.mlmodelc',
    archiveUri: 'https://example.test/fixture-encoder.mlmodelc.zip',
    archiveSha256: sha256.convert(archiveBytes).toString(),
    archiveSizeBytes: archiveBytes.length,
  ),
);

List<int> _coreMlArchive(String directoryName) {
  final archive = Archive()
    ..addFile(ArchiveFile('$directoryName/model.mil', 4, <int>[1, 2, 3, 4]));
  return ZipEncoder().encode(archive);
}

class _HangingClient extends http.BaseClient {
  final started = Completer<void>();
  final _stream = StreamController<List<int>>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    started.complete();
    return http.StreamedResponse(
      _stream.stream,
      HttpStatus.ok,
      contentLength: 4,
    );
  }

  @override
  void close() {
    if (!_stream.isClosed) {
      _stream.addError(http.ClientException('canceled'));
      unawaited(_stream.close());
    }
  }
}
