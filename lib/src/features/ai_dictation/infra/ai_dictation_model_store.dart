import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AiDictationModelStore {
  AiDictationModelStore({http.Client? client})
      : _client = client ?? http.Client();

  static const legacyModelId = 'whisper-cpp-base';
  static const modelId = 'whisper-base';
  static const modelFileName = 'ggml-base.bin';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  static final Uri modelUri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
  );

  final http.Client _client;

  static const models = <AiDictationModel>[
    AiDictationModel(
      id: 'whisper-tiny',
      label: 'Whisper Tiny',
      fileName: 'ggml-tiny.bin',
      sha256: '',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true',
      sizeBytes: 75 * 1024 * 1024,
    ),
    AiDictationModel(
      id: modelId,
      label: 'Whisper Base',
      fileName: modelFileName,
      sha256: modelSha256,
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
      sizeBytes: 142 * 1024 * 1024,
    ),
    AiDictationModel(
      id: 'whisper-small',
      label: 'Whisper Small',
      fileName: 'ggml-small.bin',
      sha256: '',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true',
      sizeBytes: 466 * 1024 * 1024,
    ),
  ];

  AiDictationModel modelFor(String id) {
    final normalized = modelForId(id);
    return models.firstWhere(
      (model) => model.id == normalized,
      orElse: () => models[1],
    );
  }

  static String modelForId(String id) => id == legacyModelId ? modelId : id;

  Future<String> modelPath([String? id]) async {
    final model = modelFor(id ?? modelId);
    final support = await getApplicationSupportDirectory();
    return p.join(
      support.path,
      'models',
      'ai-dictation',
      model.id,
      '1',
      model.fileName,
    );
  }

  Future<bool> isInstalled([String? id]) async {
    final model = modelFor(id ?? modelId);
    final path = await modelPath(model.id);
    final file = File(path);
    final marker = File('$path.sha256');
    if (!await file.exists() || !await marker.exists()) {
      return false;
    }
    final expected = model.sha256.isEmpty
        ? sha256.convert(await file.readAsBytes()).toString()
        : model.sha256;
    return (await marker.readAsString()).trim() == expected;
  }

  Future<String> download(
      {String? id, void Function(double progress)? onProgress}) async {
    final model = modelFor(id ?? modelId);
    final destination = await modelPath(model.id);
    final modelDirectory = Directory(p.dirname(destination));
    await modelDirectory.create(recursive: true);
    final staging = File(
      '$destination.download-${DateTime.now().microsecondsSinceEpoch}',
    );
    final marker = File('$destination.sha256');
    var installed = false;
    try {
      final response =
          await _client.send(http.Request('GET', Uri.parse(model.uri)));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Whisper model download failed: ${response.statusCode}.',
        );
      }
      final sink = staging.openWrite();
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        }
      }
      await sink.close();

      final digest = await Isolate.run(() => _sha256File(staging.path));
      if (model.sha256.isNotEmpty && digest != model.sha256) {
        throw StateError(
          'The downloaded Whisper model failed checksum verification.',
        );
      }
      final existing = File(destination);
      if (await existing.exists()) {
        await existing.delete();
      }
      await staging.rename(destination);
      await marker.writeAsString(digest, flush: true);
      installed = true;
      return destination;
    } finally {
      if (await staging.exists()) {
        await staging.delete();
      }
      if (!installed && await marker.exists()) {
        await marker.delete();
      }
    }
  }

  Future<void> remove([String? id]) async {
    final path = await modelPath(id);
    final modelRoot = Directory(p.dirname(path));
    if (await modelRoot.exists()) {
      await modelRoot.delete(recursive: true);
    }
  }

  void dispose() => _client.close();
}

class AiDictationModel {
  const AiDictationModel({
    required this.id,
    required this.label,
    required this.fileName,
    required this.sha256,
    required this.uri,
    required this.sizeBytes,
  });

  final String id;
  final String label;
  final String fileName;
  final String sha256;
  final String uri;
  final int sizeBytes;
}

String _sha256File(String path) {
  final bytes = File(path).readAsBytesSync();
  return sha256.convert(bytes).toString();
}
