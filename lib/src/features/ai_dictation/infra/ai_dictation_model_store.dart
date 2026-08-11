import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AiDictationModelStore {
  AiDictationModelStore({http.Client? client})
    : _client = client ?? http.Client();

  static const modelId = 'whisper-cpp-base';
  static const modelFileName = 'ggml-base.bin';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  static final Uri modelUri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
  );

  final http.Client _client;

  Future<String> modelPath() async {
    final support = await getApplicationSupportDirectory();
    return p.join(
      support.path,
      'models',
      'ai-dictation',
      modelId,
      '1',
      modelFileName,
    );
  }

  Future<bool> isInstalled() async {
    final path = await modelPath();
    final file = File(path);
    final marker = File('$path.sha256');
    if (!await file.exists() || !await marker.exists()) {
      return false;
    }
    return (await marker.readAsString()).trim() == modelSha256;
  }

  Future<String> download({void Function(double progress)? onProgress}) async {
    final destination = await modelPath();
    final modelDirectory = Directory(p.dirname(destination));
    await modelDirectory.create(recursive: true);
    final staging = File(
      '$destination.download-${DateTime.now().microsecondsSinceEpoch}',
    );
    final marker = File('$destination.sha256');
    var installed = false;
    try {
      final response = await _client.send(http.Request('GET', modelUri));
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
      if (digest != modelSha256) {
        throw StateError(
          'The downloaded Whisper model failed checksum verification.',
        );
      }
      final existing = File(destination);
      if (await existing.exists()) {
        await existing.delete();
      }
      await staging.rename(destination);
      await marker.writeAsString(modelSha256, flush: true);
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

  Future<void> remove() async {
    final path = await modelPath();
    final modelRoot = Directory(p.dirname(path));
    if (await modelRoot.exists()) {
      await modelRoot.delete(recursive: true);
    }
  }

  void dispose() => _client.close();
}

String _sha256File(String path) {
  final bytes = File(path).readAsBytesSync();
  return sha256.convert(bytes).toString();
}
