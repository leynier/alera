import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class StagedDesktopUpdate {
  const StagedDesktopUpdate({
    required this.update,
    required this.directory,
    required this.artifactPath,
    required this.payloadPath,
  });

  final AleraUpdateInfo update;
  final Directory directory;
  final String artifactPath;
  final String? payloadPath;

  Future<void> delete() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

abstract interface class AleraDesktopUpdateStager {
  Future<StagedDesktopUpdate> stage(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  });
}

class DesktopUpdateStager implements AleraDesktopUpdateStager {
  const DesktopUpdateStager({required this.client, required this.platform});

  final http.Client client;
  final String platform;

  @override
  Future<StagedDesktopUpdate> stage(
    AleraUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final expectedSize = update.size;
    final expectedSha256 = update.sha256;
    if (expectedSize == null || expectedSize <= 0 || expectedSha256 == null) {
      throw const FormatException(
        'The update artifact is missing required integrity metadata.',
      );
    }
    if (update.platform != platform) {
      throw StateError(
        'The ${update.platform} artifact cannot be installed on $platform.',
      );
    }

    final stagingDirectory = await Directory.systemTemp.createTemp(
      'alera-update-',
    );
    try {
      final artifactName = _artifactName(update.url, update.installerKind);
      final artifactPath = p.join(stagingDirectory.path, artifactName);
      await _download(
        update.url,
        artifactPath,
        expectedSize: expectedSize,
        onProgress: onProgress,
      );
      onProgress?.call(0.86);

      final actualSha256 = await Isolate.run(
        () => _sha256ForFile(artifactPath),
      );
      if (actualSha256 != expectedSha256) {
        throw const FormatException(
          'The downloaded update failed SHA-256 verification.',
        );
      }
      onProgress?.call(0.92);

      final payloadPath = await _preparePayload(
        update,
        artifactPath,
        stagingDirectory,
      );
      onProgress?.call(1);
      return StagedDesktopUpdate(
        update: update,
        directory: stagingDirectory,
        artifactPath: artifactPath,
        payloadPath: payloadPath,
      );
    } catch (_) {
      await stagingDirectory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _download(
    Uri source,
    String destination, {
    required int expectedSize,
    void Function(double progress)? onProgress,
  }) async {
    final response = await client.send(http.Request('GET', source));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Update download failed with status ${response.statusCode}.',
        uri: source,
      );
    }
    if (response.contentLength case final int contentLength
        when contentLength >= 0 && contentLength != expectedSize) {
      throw const FormatException(
        'The update download size does not match the signed manifest.',
      );
    }

    final file = File(destination);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > expectedSize) {
          throw const FormatException(
            'The update download exceeded its signed size.',
          );
        }
        sink.add(chunk);
        onProgress?.call((received / expectedSize * 0.85).clamp(0, 0.85));
      }
    } finally {
      await sink.close();
    }
    if (received != expectedSize) {
      throw const FormatException('The update download is incomplete.');
    }
  }

  Future<String?> _preparePayload(
    AleraUpdateInfo update,
    String artifactPath,
    Directory stagingDirectory,
  ) async {
    if (update.installerKind == 'deb' || update.installerKind == 'rpm') {
      return null;
    }
    if (update.installerKind != 'tar.gz') {
      throw StateError(
        'Automatic installation does not support '
        '${update.installerKind} artifacts.',
      );
    }

    final payloadDirectory = Directory(
      p.join(stagingDirectory.path, 'payload'),
    );
    await Isolate.run(
      () => extractFileToDisk(artifactPath, payloadDirectory.path),
    );
    final payloadPath = switch (platform) {
      'macos' => p.join(payloadDirectory.path, 'Alera.app'),
      'windows' || 'linux' => payloadDirectory.path,
      _ => throw StateError('Automatic installation is unavailable.'),
    };
    final executablePath = switch (platform) {
      'macos' => p.join(payloadPath, 'Contents', 'MacOS', 'Alera'),
      'windows' => p.join(payloadPath, 'Alera.exe'),
      'linux' => p.join(payloadPath, 'alera'),
      _ => throw StateError('Automatic installation is unavailable.'),
    };
    if (!await File(executablePath).exists()) {
      throw const FormatException(
        'The update archive does not contain the Alera executable.',
      );
    }
    return payloadPath;
  }
}

String _artifactName(Uri uri, String installerKind) {
  final basename = p.posix.basename(uri.path);
  if (basename.isNotEmpty && basename != '/') {
    return basename;
  }
  return 'alera-update.$installerKind';
}

Future<String> _sha256ForFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
