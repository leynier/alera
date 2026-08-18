import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MobileAiDictationModel {
  const MobileAiDictationModel({
    required this.id,
    required this.label,
    required this.description,
    required this.fileName,
    required this.uri,
    required this.sha256,
    required this.sizeBytes,
  });

  final String id;
  final String label;
  final String description;
  final String fileName;
  final String uri;
  final String sha256;
  final int sizeBytes;
}

class MobileAiDictationModelStore {
  MobileAiDictationModelStore({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? supportDirectory,
    List<MobileAiDictationModel>? catalog,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _supportDirectory =
           supportDirectory ?? (() => getApplicationSupportDirectory()),
       catalog = catalog ?? models;

  static const models = <MobileAiDictationModel>[
    MobileAiDictationModel(
      id: 'whisper-tiny',
      label: 'Whisper Tiny',
      description: 'Fastest and lightest, with lower accuracy.',
      fileName: 'ggml-tiny.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      sizeBytes: 77691713,
    ),
    MobileAiDictationModel(
      id: 'whisper-base',
      label: 'Whisper Base',
      description: 'Balanced speed and accuracy. Recommended.',
      fileName: 'ggml-base.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
      sizeBytes: 147951465,
    ),
    MobileAiDictationModel(
      id: 'whisper-small',
      label: 'Whisper Small',
      description: 'More accurate, with higher memory and battery use.',
      fileName: 'ggml-small.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
      sizeBytes: 487601967,
    ),
  ];

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _supportDirectory;
  final List<MobileAiDictationModel> catalog;
  http.Client? _activeClient;
  String? _activeModelId;
  Completer<void>? _activeFinished;
  bool _cancelRequested = false;

  MobileAiDictationModel modelFor(String id) => catalog.firstWhere(
    (model) => model.id == id,
    orElse: () => catalog.firstWhere((model) => model.id == 'whisper-base'),
  );

  Future<String> modelPath(String id) async {
    final model = modelFor(id);
    final support = await _supportDirectory();
    return p.join(
      support.path,
      'models',
      'ai-dictation',
      model.id,
      '1',
      model.fileName,
    );
  }

  Future<String> partialPath(String id) async => '${await modelPath(id)}.part';
  Future<String> intentPath(String id) async =>
      '${await modelPath(id)}.resume.json';

  Future<bool> isInstalled(String id) async {
    final model = modelFor(id);
    final path = await modelPath(id);
    final file = File(path);
    final marker = File('$path.sha256');
    return await file.exists() &&
        await marker.exists() &&
        await file.length() == model.sizeBytes &&
        (await marker.readAsString()).trim() == model.sha256;
  }

  Future<int> partialBytes(String id) async {
    final file = File(await partialPath(id));
    return await file.exists() ? file.length() : 0;
  }

  Future<Set<String>> resumableModelIds() async {
    final result = <String>{};
    for (final model in catalog) {
      if (await File(await intentPath(model.id)).exists()) result.add(model.id);
    }
    return result;
  }

  Future<String> download(
    String id, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (_activeClient != null) {
      throw StateError('Another Whisper model download is already active.');
    }
    final model = modelFor(id);
    final destination = await modelPath(id);
    final partial = File(await partialPath(id));
    final intent = File(await intentPath(id));
    await Directory(p.dirname(destination)).create(recursive: true);
    await intent.writeAsString(
      jsonEncode(<String, Object?>{
        'modelId': model.id,
        'sha256': model.sha256,
        'sizeBytes': model.sizeBytes,
      }),
      flush: true,
    );
    final client = _clientFactory();
    _activeClient = client;
    _activeModelId = id;
    final finished = Completer<void>();
    _activeFinished = finished;
    _cancelRequested = false;
    try {
      var offset = await partialBytes(id);
      if (offset > model.sizeBytes) {
        await partial.delete();
        offset = 0;
      }
      if (offset < model.sizeBytes) {
        final request = http.Request('GET', Uri.parse(model.uri));
        if (offset > 0) {
          request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';
        }
        final response = await client.send(request);
        if (offset > 0 && response.statusCode == HttpStatus.partialContent) {
          _validateContentRange(response, offset, model.sizeBytes);
        } else if (offset > 0) {
          if (await partial.exists()) await partial.delete();
          offset = 0;
        }
        if (!<int>[
          HttpStatus.ok,
          HttpStatus.partialContent,
        ].contains(response.statusCode)) {
          throw HttpException(
            'Model download failed with HTTP ${response.statusCode}.',
          );
        }
        final sink = partial.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        var received = offset;
        try {
          await for (final chunk in response.stream) {
            if (_cancelRequested) throw const MobileAiModelDownloadCancelled();
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, model.sizeBytes);
          }
        } finally {
          await sink.close();
        }
      }
      if (_cancelRequested) throw const MobileAiModelDownloadCancelled();
      if (!await partial.exists() ||
          await partial.length() != model.sizeBytes) {
        throw StateError('The model download ended before it was complete.');
      }
      final digest = await Isolate.run(
        () async =>
            (await sha256.bind(File(partial.path).openRead()).first).toString(),
      );
      if (digest != model.sha256) {
        await partial.delete();
        throw StateError('The downloaded model failed verification.');
      }
      final installed = File(destination);
      if (await installed.exists()) await installed.delete();
      await partial.rename(destination);
      await File('$destination.sha256').writeAsString(digest, flush: true);
      if (await intent.exists()) await intent.delete();
      onProgress?.call(model.sizeBytes, model.sizeBytes);
      return destination;
    } on Object {
      if (_cancelRequested) {
        throw const MobileAiModelDownloadCancelled();
      }
      rethrow;
    } finally {
      client.close();
      _activeClient = null;
      _activeModelId = null;
      _activeFinished = null;
      if (!finished.isCompleted) finished.complete();
    }
  }

  Future<void> cancel(String id) async {
    if (_activeModelId == id) {
      _cancelRequested = true;
      _activeClient?.close();
      await _activeFinished?.future;
    }
    for (final path in <String>[await partialPath(id), await intentPath(id)]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> remove(String id) async {
    await cancel(id);
    final directory = Directory(p.dirname(await modelPath(id)));
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class MobileAiModelDownloadCancelled implements Exception {
  const MobileAiModelDownloadCancelled();
}

void _validateContentRange(
  http.StreamedResponse response,
  int expectedStart,
  int expectedTotal,
) {
  final value = response.headers[HttpHeaders.contentRangeHeader];
  final match = value == null
      ? null
      : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
  if (match == null ||
      int.parse(match.group(1)!) != expectedStart ||
      int.parse(match.group(3)!) != expectedTotal) {
    throw const HttpException('The model resume response was invalid.');
  }
}
