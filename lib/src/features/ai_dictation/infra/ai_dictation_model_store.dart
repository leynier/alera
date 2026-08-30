import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ai_dictation_core_ml_store.dart';
import 'ai_dictation_model.dart';

export 'ai_dictation_model.dart';

class AiDictationModelStore({
  http.Client Function()? clientFactory,
  Future<Directory> Function()? supportDirectory,
  List<AiDictationModel>? modelCatalog,
  bool? installCoreMlEncoder,
  AiDictationCoreMlStore? coreMlStore,
}) {
  this
    : _clientFactory = clientFactory ?? http.Client.new,
      _supportDirectory =
          supportDirectory ?? (() => getApplicationSupportDirectory()),
      _modelCatalog = modelCatalog ?? models,
      _installCoreMlEncoder = installCoreMlEncoder ?? Platform.isMacOS,
      _coreMlStore = coreMlStore ?? const AiDictationCoreMlStore();

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
      uri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true',
      sizeBytes: 77691713,
      coreMlEncoder: AiDictationCoreMlEncoder(
        directoryName: 'ggml-tiny-encoder.mlmodelc',
        archiveUri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-encoder.mlmodelc.zip?download=true',
        archiveSha256:
            'c88cbd2648e1f5415092bcf5256add463a0f19943e6938f46e8d4ffdebd47739',
        archiveSizeBytes: 15037446,
      ),
    ),
    AiDictationModel(
      id: modelId,
      label: 'Whisper Base',
      description: 'Balanced speed and accuracy. Recommended for most devices.',
      fileName: modelFileName,
      sha256: modelSha256,
      uri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
      sizeBytes: 147951465,
      coreMlEncoder: AiDictationCoreMlEncoder(
        directoryName: 'ggml-base-encoder.mlmodelc',
        archiveUri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-encoder.mlmodelc.zip?download=true',
        archiveSha256:
            '7e6ab77041942572f239b5b602f8aaa1c3ed29d73e3d8f20abea03a773541089',
        archiveSizeBytes: 37922638,
      ),
    ),
    AiDictationModel(
      id: 'whisper-small',
      label: 'Whisper Small',
      description: 'Improved accuracy with slower transcription.',
      fileName: 'ggml-small.bin',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
      uri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true',
      sizeBytes: 487601967,
      coreMlEncoder: AiDictationCoreMlEncoder(
        directoryName: 'ggml-small-encoder.mlmodelc',
        archiveUri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-encoder.mlmodelc.zip?download=true',
        archiveSha256:
            'de43fb9fed471e95c19e60ae67575c2bf09e8fb607016da171b06ddad313988b',
        archiveSizeBytes: 163083239,
      ),
    ),
    AiDictationModel(
      id: 'whisper-large-v3-turbo-q5-0',
      label: 'Whisper Large V3 Turbo Q5_0',
      description: 'Highest curated accuracy with the largest memory cost.',
      fileName: 'ggml-large-v3-turbo-q5_0.bin',
      sha256:
          '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
      uri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true',
      sizeBytes: 574041195,
      coreMlEncoder: AiDictationCoreMlEncoder(
        directoryName: 'ggml-large-v3-turbo-encoder.mlmodelc',
        archiveUri: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip?download=true',
        archiveSha256:
            '84bedfe895bd7b5de6e8e89a0803dfc5addf8c0c5bc4c937451716bf7cf7988a',
        archiveSizeBytes: 1173393014,
      ),
    ),
  ];

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _supportDirectory;
  final List<AiDictationModel> _modelCatalog;
  final bool _installCoreMlEncoder;
  final AiDictationCoreMlStore _coreMlStore;
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

  int downloadSizeBytes(String id) {
    final model = modelFor(id);
    final encoder = _requiredCoreMlEncoder(model);
    return model.sizeBytes + (encoder?.archiveSizeBytes ?? 0);
  }

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
    if (!await _isModelInstalled(model, path)) return false;
    final encoder = _requiredCoreMlEncoder(model);
    return encoder == null || await _coreMlStore.isInstalled(path, encoder);
  }

  Future<bool> _isModelInstalled(AiDictationModel model, String path) async {
    final file = File(path);
    final marker = File('$path.sha256');
    if (!await file.exists() || !await marker.exists()) return false;
    if (await file.length() != model.sizeBytes) return false;
    return (await marker.readAsString()).trim() == model.sha256;
  }

  Future<int> partialBytes([String? id]) async {
    final model = modelFor(id ?? modelId);
    final path = await modelPath(model.id);
    if (await _isModelInstalled(model, path)) {
      final encoder = _requiredCoreMlEncoder(model);
      return model.sizeBytes +
          (encoder == null
              ? 0
              : await _coreMlStore.partialBytes(path, encoder));
    }
    final file = File(await partialPath(model.id));
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
        'sizeBytes': downloadSizeBytes(model.id),
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
      final totalBytes = downloadSizeBytes(model.id);
      var offset = await _isModelInstalled(model, destination)
          ? model.sizeBytes
          : await partial.exists()
          ? await partial.length()
          : 0;
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
              onProgress?.call((received / totalBytes).clamp(0, 1));
            }
          } finally {
            await sink.close();
          }
        }
      }
      if (!await _isModelInstalled(model, destination)) {
        if (_cancelRequested) throw const AiDictationDownloadCancelled();
        if (!await partial.exists() ||
            await partial.length() != model.sizeBytes) {
          throw StateError(
            'The Whisper model download ended before it was complete.',
          );
        }
        final digest = await Isolate.run(_Sha256Computation(partial.path).call);
        if (digest != model.sha256) {
          throw StateError(
            'The downloaded Whisper model failed checksum verification.',
          );
        }
        final installed = File(destination);
        if (await installed.exists()) await installed.delete();
        await partial.rename(destination);
        await File('$destination.sha256').writeAsString(digest, flush: true);
      }
      final encoder = _requiredCoreMlEncoder(model);
      if (encoder != null) {
        await _coreMlStore.download(
          client: client,
          modelPath: destination,
          encoder: encoder,
          isCancelled: () => _cancelRequested,
          onProgress: (received) => onProgress?.call(
            ((model.sizeBytes + received) / totalBytes).clamp(0, 1),
          ),
        );
      }
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
    final modelPath = await this.modelPath(id);
    for (final path in <String>[
      await partialPath(id),
      await resumeIntentPath(id),
    ]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _coreMlStore.discardPartial(modelPath);
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

  AiDictationCoreMlEncoder? _requiredCoreMlEncoder(AiDictationModel model) =>
      _installCoreMlEncoder ? model.coreMlEncoder : null;
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

class const _Sha256Computation(final String path) {
  Future<String> call() => _sha256File(path);
}
