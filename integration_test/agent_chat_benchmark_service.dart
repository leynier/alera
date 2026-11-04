import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:path/path.dart' as p;

const _serviceInfoPath = String.fromEnvironment(
  'ALERA_AGENT_CHAT_BENCHMARK_SERVICE_INFO',
);
const _readinessTimeout = Duration(seconds: 10);
const _pollInterval = Duration(milliseconds: 100);

/// Publishes this benchmark's existing service only when explicitly requested.
Future<void> writeAgentChatBenchmarkServiceInfo({
  String outputPath = _serviceInfoPath,
  Future<Uri?> Function()? readServiceUri,
  Duration readinessTimeout = _readinessTimeout,
}) async {
  if (outputPath.isEmpty) return;
  if (!Platform.isMacOS && !Platform.isLinux) {
    throw StateError('Benchmark service evidence requires POSIX permissions.');
  }
  final file = await _validateOutputPath(outputPath);
  final stopwatch = Stopwatch()..start();
  final readUri = readServiceUri ?? _readServiceUri;
  Uri? uri;
  while (stopwatch.elapsed < readinessTimeout) {
    final remaining = readinessTimeout - stopwatch.elapsed;
    try {
      uri = await readUri().timeout(remaining);
    } on TimeoutException {
      break;
    }
    if (uri != null) break;
    final pause = readinessTimeout - stopwatch.elapsed;
    if (pause > Duration.zero) {
      await Future.pause(pause < _pollInterval ? pause : _pollInterval);
    }
  }
  if (uri == null) {
    throw StateError('Benchmark VM service was not ready within the deadline.');
  }
  _validateServiceUri(uri);
  // The private directory protects the empty file before chmod; no URI is
  // written until its permissions are 0600. Never overwrite earlier evidence.
  await _validateOutputPath(outputPath);
  await file.create(exclusive: true);
  try {
    if (!setPosixFileMode(file.path, posixPrivateFileMode) ||
        (await file.stat()).mode & 0xFFF != posixPrivateFileMode) {
      throw StateError('Could not secure benchmark service evidence.');
    }
    await file.writeAsString(
      '${jsonEncode(<String, Object>{'pid': pid, 'uri': uri.toString()})}\n',
      flush: true,
    );
  } catch (_) {
    await file.delete();
    rethrow;
  }
}

Future<Uri?> _readServiceUri() async =>
    (await developer.Service.getInfo()).serverUri;

Future<File> _validateOutputPath(String outputPath) async {
  if (!p.isAbsolute(outputPath) ||
      p.normalize(outputPath) != outputPath ||
      outputPath.endsWith('/') ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(outputPath)) {
    throw StateError('Benchmark service evidence needs a clean absolute path.');
  }
  final file = File(outputPath);
  final directory = file.parent;
  final stat = await directory.stat();
  if (stat.type != FileSystemEntityType.directory ||
      stat.mode & 0xFFF != posixPrivateDirectoryMode ||
      await directory.resolveSymbolicLinks() != directory.path) {
    throw StateError(
      'Benchmark evidence needs an existing private 0700 directory.',
    );
  }
  if (await FileSystemEntity.type(outputPath, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Benchmark service evidence must be a fresh file.');
  }
  return file;
}

void _validateServiceUri(Uri uri) {
  final address = InternetAddress.tryParse(uri.host);
  if (uri.scheme != 'http' ||
      address == null ||
      !address.isLoopback ||
      !uri.hasPort ||
      uri.port <= 0 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !RegExp(r'^/[A-Za-z0-9_-]+={0,2}/$').hasMatch(uri.path)) {
    throw StateError('Benchmark VM service must be authenticated on loopback.');
  }
}
