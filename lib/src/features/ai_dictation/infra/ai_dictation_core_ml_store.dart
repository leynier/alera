import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai_dictation_model.dart';

class AiDictationCoreMlStore {
  const AiDictationCoreMlStore();

  String encoderPath(String modelPath, AiDictationCoreMlEncoder encoder) =>
      p.join(p.dirname(modelPath), encoder.directoryName);

  String partialPath(String modelPath) => '$modelPath.coreml.part.zip';

  String stagingPath(String modelPath) => '$modelPath.coreml.installing';

  Future<bool> isInstalled(
    String modelPath,
    AiDictationCoreMlEncoder encoder,
  ) async {
    final destination = Directory(encoderPath(modelPath, encoder));
    final marker = File(p.join(destination.path, '.archive.sha256'));
    if (!await destination.exists() || !await marker.exists()) return false;
    return (await marker.readAsString()).trim() == encoder.archiveSha256;
  }

  Future<int> partialBytes(
    String modelPath,
    AiDictationCoreMlEncoder encoder,
  ) async {
    if (await isInstalled(modelPath, encoder)) return encoder.archiveSizeBytes;
    final partial = File(partialPath(modelPath));
    return await partial.exists() ? partial.length() : 0;
  }

  Future<void> download({
    required http.Client client,
    required String modelPath,
    required AiDictationCoreMlEncoder encoder,
    required bool Function() isCancelled,
    required void Function(int receivedBytes) onProgress,
  }) async {
    if (await isInstalled(modelPath, encoder)) {
      onProgress(encoder.archiveSizeBytes);
      return;
    }

    final partial = File(partialPath(modelPath));
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > encoder.archiveSizeBytes) {
      await partial.delete();
      offset = 0;
    }
    onProgress(offset);

    if (offset < encoder.archiveSizeBytes) {
      final request = http.Request('GET', Uri.parse(encoder.archiveUri));
      if (offset > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';
      }
      final response = await client.send(request);
      if (offset > 0 && response.statusCode == HttpStatus.partialContent) {
        _validateContentRange(response, offset, encoder.archiveSizeBytes);
      } else if (response.statusCode == HttpStatus.ok) {
        if (offset > 0 && await partial.exists()) await partial.delete();
        offset = 0;
      } else if (response.statusCode !=
              HttpStatus.requestedRangeNotSatisfiable ||
          offset != encoder.archiveSizeBytes) {
        throw HttpException(
          'Whisper Core ML encoder download failed: ${response.statusCode}.',
        );
      }

      if (response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
        final sink = partial.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        var received = offset;
        try {
          await for (final chunk in response.stream) {
            if (isCancelled()) throw const AiDictationDownloadCancelled();
            sink.add(chunk);
            received += chunk.length;
            onProgress(received);
          }
        } finally {
          await sink.close();
        }
      }
    }

    if (isCancelled()) throw const AiDictationDownloadCancelled();
    if (!await partial.exists() ||
        await partial.length() != encoder.archiveSizeBytes) {
      throw StateError(
        'The Whisper Core ML encoder download ended before it was complete.',
      );
    }
    final digest = await Isolate.run(_Sha256Computation(partial.path).call);
    if (digest != encoder.archiveSha256) {
      throw StateError(
        'The downloaded Whisper Core ML encoder failed checksum verification.',
      );
    }

    final staging = Directory(stagingPath(modelPath));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      final extraction = _CoreMlArchiveExtraction(
        archivePath: partial.path,
        outputPath: staging.path,
      );
      await Isolate.run(extraction.call);
      final extracted = Directory(p.join(staging.path, encoder.directoryName));
      if (!await extracted.exists()) {
        throw StateError(
          'The Whisper Core ML encoder archive did not contain the expected model.',
        );
      }
      if (isCancelled()) throw const AiDictationDownloadCancelled();
      await File(
        p.join(extracted.path, '.archive.sha256'),
      ).writeAsString(digest, flush: true);
      final destination = Directory(encoderPath(modelPath, encoder));
      if (await destination.exists()) await destination.delete(recursive: true);
      await extracted.rename(destination.path);
      await partial.delete();
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    onProgress(encoder.archiveSizeBytes);
  }

  Future<void> discardPartial(String modelPath) async {
    final partial = File(partialPath(modelPath));
    if (await partial.exists()) await partial.delete();
    final staging = Directory(stagingPath(modelPath));
    if (await staging.exists()) await staging.delete(recursive: true);
  }
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
    throw const HttpException(
      'Whisper Core ML encoder resume response was invalid.',
    );
  }
}

Future<String> _sha256File(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

class _Sha256Computation {
  const _Sha256Computation(this.path);

  final String path;

  Future<String> call() => _sha256File(path);
}

class _CoreMlArchiveExtraction {
  const _CoreMlArchiveExtraction({
    required this.archivePath,
    required this.outputPath,
  });

  final String archivePath;
  final String outputPath;

  Future<void> call() => extractFileToDisk(archivePath, outputPath);
}
