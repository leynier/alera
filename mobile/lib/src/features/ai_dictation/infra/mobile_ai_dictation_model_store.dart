import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef MobileSupportDirectory = Future<Directory> Function();

abstract interface class MobileAiDictationModels {
  Future<bool> isInstalled();

  Future<String> download({void Function(double)? onProgress});

  void dispose();
}

final class MobileAiModelDownloadCancelled implements Exception {
  const MobileAiModelDownloadCancelled();
}

final class MobileAiModelDownloadException implements Exception {
  const MobileAiModelDownloadException([this.cause]);

  final Object? cause;

  static const message =
      'The model download was interrupted. Check your connection and retry.';

  @override
  String toString() => message;
}

class MobileAiDictationModelStore implements MobileAiDictationModels {
  static const modelId = 'whisper-base';
  static const modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true';
  static const modelSha256 =
      '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe';
  MobileAiDictationModelStore({
    http.Client? client,
    Uri? downloadUrl,
    String? expectedSha256,
    MobileSupportDirectory? supportDirectory,
  }) : _client = client ?? http.Client(),
       _downloadUrl = downloadUrl ?? Uri.parse(modelUrl),
       _expectedSha256 = expectedSha256 ?? modelSha256,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final http.Client _client;
  final Uri _downloadUrl;
  final String _expectedSha256;
  final MobileSupportDirectory _supportDirectory;
  bool _disposed = false;

  Future<String> path() async {
    final root = await _supportDirectory();
    return p.join(
      root.path,
      'models',
      'ai-dictation',
      modelId,
      'ggml-base.bin',
    );
  }

  @override
  Future<bool> isInstalled() async {
    final file = File(await path());
    if (!await file.exists()) {
      return false;
    }
    return await Isolate.run(() => _sha256File(file.path)) == _expectedSha256;
  }

  @override
  Future<String> download({void Function(double)? onProgress}) async {
    _throwIfDisposed();
    final destination = await path();
    _throwIfDisposed();
    await Directory(p.dirname(destination)).create(recursive: true);
    final staging = File('$destination.download');
    await _deleteIfExists(staging);
    IOSink? sink;
    try {
      final response = await _client.send(http.Request('GET', _downloadUrl));
      if (response.statusCode != 200) {
        throw const MobileAiModelDownloadException();
      }
      sink = staging.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (response.contentLength != null && response.contentLength! > 0) {
          onProgress?.call(received / response.contentLength!);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _throwIfDisposed();
      final digest = await Isolate.run(() => _sha256File(staging.path));
      _throwIfDisposed();
      if (digest != _expectedSha256) {
        throw const MobileAiModelDownloadException();
      }
      await _deleteIfExists(File(destination));
      await staging.rename(destination);
      return destination;
    } on Object catch (error, stackTrace) {
      if (sink != null) {
        try {
          await sink.close();
        } on Object {
          // Preserve the transfer error that caused cleanup.
        }
      }
      await _deleteIfExists(staging);
      if (_disposed) {
        throw const MobileAiModelDownloadCancelled();
      }
      if (error is MobileAiModelDownloadException) rethrow;
      if (error is http.ClientException ||
          error is SocketException ||
          error is HttpException ||
          error is TimeoutException) {
        Error.throwWithStackTrace(
          MobileAiModelDownloadException(error),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<void> remove() async {
    final file = File(await path());
    if (await file.exists()) await file.delete();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close();
  }

  void _throwIfDisposed() {
    if (_disposed) throw const MobileAiModelDownloadCancelled();
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

String _sha256File(String path) {
  return sha256.convert(File(path).readAsBytesSync()).toString();
}
