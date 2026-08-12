import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MobileAiDictationModelStore {
  static const modelId = 'whisper-base';
  static const modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  MobileAiDictationModelStore({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  Future<String> path() async {
    final root = await getApplicationSupportDirectory();
    return p.join(
        root.path, 'models', 'ai-dictation', modelId, 'ggml-base.bin');
  }

  Future<bool> isInstalled() async {
    final file = File(await path());
    if (!await file.exists()) return false;
    return sha256.convert(await file.readAsBytes()).toString() == modelSha256;
  }

  Future<String> download({void Function(double)? onProgress}) async {
    final destination = await path();
    await Directory(p.dirname(destination)).create(recursive: true);
    final staging = File('$destination.download');
    final response =
        await _client.send(http.Request('GET', Uri.parse(modelUrl)));
    if (response.statusCode != 200)
      throw HttpException('Whisper model download failed.');
    final sink = staging.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (response.contentLength != null && response.contentLength! > 0)
        onProgress?.call(received / response.contentLength!);
    }
    await sink.close();
    if (await File(destination).exists()) await File(destination).delete();
    await staging.rename(destination);
    if (sha256.convert(await File(destination).readAsBytes()).toString() !=
        modelSha256) {
      await File(destination).delete();
      throw StateError('The downloaded Whisper model failed verification.');
    }
    return destination;
  }

  Future<void> remove() async {
    final file = File(await path());
    if (await file.exists()) await file.delete();
  }

  void dispose() => _client.close();
}
