import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AiDictationModelStore {
  AiDictationModelStore({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? supportDirectory,
    List<AiDictationModel>? modelCatalog,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _supportDirectory =
           supportDirectory ?? (() => getApplicationSupportDirectory()),
       _modelCatalog = modelCatalog ?? models;

  static const legacyModelId = 'whisper-cpp-base';
  static const modelId = 'whisper-base';
  static const modelFileName = 'ggml-base.bin';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  static final Uri modelUri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
  );

  static const models = <AiDictationModel>[
    AiDictationModel(
      id: 'whisper-tiny',
      label: 'Whisper Tiny',
      description: 'Fastest, with lower transcription accuracy.',
      fileName: 'ggml-tiny.bin',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true',
      sizeBytes: 77691713,
    ),
    AiDictationModel(
      id: modelId,
      label: 'Whisper Base',
      description: 'Balanced speed and accuracy. Recommended for most devices.',
      fileName: modelFileName,
      sha256: modelSha256,
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
      sizeBytes: 147951465,
    ),
    AiDictationModel(
      id: 'whisper-small',
      label: 'Whisper Small',
      description: 'Improved accuracy with slower transcription.',
      fileName: 'ggml-small.bin',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true',
      sizeBytes: 487601967,
    ),
    AiDictationModel(
      id: 'whisper-large-v3-turbo-q5-0',
      label: 'Whisper Large V3 Turbo Q5_0',
      description: 'Highest curated accuracy with the largest memory cost.',
      fileName: 'ggml-large-v3-turbo-q5_0.bin',
      sha256:
          '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true',
      sizeBytes: 574041195,
    ),
  ];

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _supportDirectory;
  final List<AiDictationModel> _modelCatalog;
  http.Client? _activeClient;
  String? _activeModelId;
  Completer<void>? _activeFinished;
  bool _cancelRequested = false;

  AiDictationModel modelFor(String id) {
    final normalized = modelForId(id);
    return _modelCatalog.firstWhere(
      (model) => model.id == normalized,
      orElse: () =>
          _modelCatalog.length > 1 ? _modelCatalog[1] : _modelCatalog.first,
    );
  }

  static String modelForId(String id) => id == legacyModelId ? modelId : id;

  Future<String> modelPath([String? id]) async {
    final model = modelFor(id ?? modelId);
    final support = await _supportDirectory();
    return p.join(
      support.path,
      'models',
      'ai-dictation',
      model.id,
      model.storageVersion.toString(),
      model.fileName,
    );
  }

  Future<String> partialPath([String? id]) async =>
      '${await modelPath(id)}.part';

  Future<String> resumeIntentPath([String? id]) async =>
      '${await modelPath(id)}.resume.json';

  Future<bool> isInstalled([String? id]) async {
    final model = modelFor(id ?? modelId);
    final path = await modelPath(model.id);
    final file = File(path);
    final marker = File('$path.sha256');
    if (!await file.exists() || !await marker.exists()) return false;
    if (await file.length() != model.sizeBytes) return false;
    return (await marker.readAsString()).trim() == model.sha256;
  }

  Future<int> partialBytes([String? id]) async {
    final file = File(await partialPath(id));
    return await file.exists() ? file.length() : 0;
  }

  Future<List<String>> resumeIntentIds() async {
    final ids = <String>[];
    for (final model in _modelCatalog) {
      if (await File(await resumeIntentPath(model.id)).exists()) {
        ids.add(model.id);
      }
    }
    return ids;
  }

  Future<String> download({
    String? id,
    void Function(double progress)? onProgress,
  }) async {
    final model = modelFor(id ?? modelId);
    if (_activeClient != null) {
      throw StateError('Another Whisper model download is already running.');
    }
    final destination = await modelPath(model.id);
    final partial = File(await partialPath(model.id));
    final intent = File(await resumeIntentPath(model.id));
    await Directory(p.dirname(destination)).create(recursive: true);
    await intent.writeAsString(
      jsonEncode(<String, Object?>{
        'modelId': model.id,
        'sha256': model.sha256,
        'sizeBytes': model.sizeBytes,
        'storageVersion': model.storageVersion,
      }),
      flush: true,
    );

    final client = _clientFactory();
    final finished = Completer<void>();
    _activeClient = client;
    _activeModelId = model.id;
    _activeFinished = finished;
    _cancelRequested = false;
    try {
      var offset = await partialBytes(model.id);
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
        } else if (response.statusCode == HttpStatus.ok) {
          if (offset > 0 && await partial.exists()) await partial.delete();
          offset = 0;
        } else if (response.statusCode ==
                HttpStatus.requestedRangeNotSatisfiable &&
            offset == model.sizeBytes) {
          // A complete partial file only needs verification.
        } else {
          throw HttpException(
            'Whisper model download failed: ${response.statusCode}.',
          );
        }
        if (response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
          final sink = partial.openWrite(
            mode: offset == 0 ? FileMode.write : FileMode.append,
          );
          var received = offset;
          try {
            await for (final chunk in response.stream) {
              if (_cancelRequested) throw const AiDictationDownloadCancelled();
              sink.add(chunk);
              received += chunk.length;
              onProgress?.call((received / model.sizeBytes).clamp(0, 1));
            }
          } finally {
            await sink.close();
          }
        }
      }
      if (_cancelRequested) throw const AiDictationDownloadCancelled();
      if (!await partial.exists() ||
          await partial.length() != model.sizeBytes) {
        throw StateError(
          'The Whisper model download ended before it was complete.',
        );
      }
      final digest = await Isolate.run(() => _sha256File(partial.path));
      if (digest != model.sha256) {
        throw StateError(
          'The downloaded Whisper model failed checksum verification.',
        );
      }
      final installed = File(destination);
      if (await installed.exists()) await installed.delete();
      await partial.rename(destination);
      await File('$destination.sha256').writeAsString(digest, flush: true);
      if (await intent.exists()) await intent.delete();
      onProgress?.call(1);
      return destination;
    } on Object catch (_) {
      if (_cancelRequested) throw const AiDictationDownloadCancelled();
      rethrow;
    } finally {
      client.close();
      _activeClient = null;
      _activeModelId = null;
      _activeFinished = null;
      if (!finished.isCompleted) finished.complete();
    }
  }

  Future<void> cancelDownload([String? id]) async {
    final normalized = id == null ? _activeModelId : modelForId(id);
    if (_activeModelId == normalized) {
      _cancelRequested = true;
      _activeClient?.close();
      await _activeFinished?.future;
    }
    if (normalized != null) await _discardPartial(normalized);
  }

  Future<void> _discardPartial(String id) async {
    for (final path in <String>[
      await partialPath(id),
      await resumeIntentPath(id),
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> remove([String? id]) async {
    final path = await modelPath(id);
    final modelRoot = Directory(p.dirname(path));
    if (await modelRoot.exists()) await modelRoot.delete(recursive: true);
  }

  void dispose() {
    _cancelRequested = true;
    _activeClient?.close();
  }
}

class AiDictationModel {
  const AiDictationModel({
    required this.id,
    required this.label,
    required this.description,
    required this.fileName,
    required this.sha256,
    required this.uri,
    required this.sizeBytes,
    this.storageVersion = 1,
  });

  final String id;
  final String label;
  final String description;
  final String fileName;
  final String sha256;
  final String uri;
  final int sizeBytes;
  final int storageVersion;
}

class AiDictationDownloadCancelled implements Exception {
  const AiDictationDownloadCancelled();
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
    throw const HttpException('Whisper model resume response was invalid.');
  }
}

Future<String> _sha256File(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
