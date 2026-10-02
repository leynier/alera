import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:alera/src/features/updater/infra/bounded_update_transport.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  HttpServer? server;

  setUp(() {
    root = Directory.systemTemp.createTempSync('alera-bounded-update');
  });

  tearDown(() async {
    await server?.close(force: true);
    server = null;
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test(
    'rejects a chunked response before it exceeds the signed length',
    () async {
      server = await _serve((request) async {
        try {
          request.response.add(<int>[1, 2, 3, 4]);
          await request.response.flush();
          request.response.add(<int>[5]);
          await request.response.close();
        } on Object {
          // The client closes the response as soon as the size ceiling trips.
        }
      });
      final transport = BoundedUpdateTransport(
        maxBytes: 4,
        timeout: const Duration(seconds: 1),
      );
      final destination = File('${root.path}/artifact.zip');

      await expectLater(
        _download(transport, _serverUri(server!), destination),
        throwsA(
          isA<UpdateArtifactTooLargeException>().having(
            (error) => error.expectedBytes,
            'expectedBytes',
            4,
          ),
        ),
      );
      transport.close();

      expect(destination.existsSync(), isFalse);
      expect(File('${destination.path}.part').existsSync(), isFalse);
    },
  );

  test('times out an idle response and removes its partial file', () async {
    final bodySent = Completer<void>();
    final release = Completer<void>();
    server = await _serve((request) async {
      try {
        request.response.add(<int>[1]);
        await request.response.flush();
        bodySent.complete();
        await release.future;
      } on Object {
        // The client aborts the response after the idle timeout.
      }
    });
    final transport = BoundedUpdateTransport(
      maxBytes: 4,
      timeout: const Duration(milliseconds: 40),
    );
    final destination = File('${root.path}/artifact.zip');
    final download = _download(transport, _serverUri(server!), destination);

    await bodySent.future;
    await expectLater(download, throwsA(isA<TimeoutException>()));
    release.complete();
    transport.close();

    expect(destination.existsSync(), isFalse);
    expect(File('${destination.path}.part').existsSync(), isFalse);
  });

  test('cancels a response that never reaches EOF', () async {
    final bodySent = Completer<void>();
    final release = Completer<void>();
    server = await _serve((request) async {
      try {
        request.response.add(<int>[1]);
        await request.response.flush();
        bodySent.complete();
        await release.future;
      } on Object {
        // The client closes the response on cancellation.
      }
    });
    final transport = BoundedUpdateTransport(
      maxBytes: 4,
      timeout: const Duration(seconds: 1),
    );
    final destination = File('${root.path}/artifact.zip');
    final download = _download(transport, _serverUri(server!), destination);

    await bodySent.future;
    await transport.cancel();
    await expectLater(
      download.timeout(const Duration(seconds: 1)),
      throwsA(isA<UpdateDownloadCancelledException>()),
    );
    release.complete();
    transport.close();

    expect(destination.existsSync(), isFalse);
    expect(File('${destination.path}.part').existsSync(), isFalse);
  });

  test(
    'settles a response cancelled before its first listener attaches',
    () async {
      final bodySent = Completer<void>();
      final release = Completer<void>();
      server = await _serve((request) async {
        try {
          request.response.add(<int>[1]);
          await request.response.flush();
          bodySent.complete();
          await release.future;
        } on Object {
          // The response remains open until the transport is cancelled.
        }
      });
      final transport = BoundedUpdateTransport(
        maxBytes: 4,
        timeout: const Duration(seconds: 1),
      );

      try {
        final response = await transport.send(
          http.Request('GET', _serverUri(server!)),
        );
        await bodySent.future;
        await transport.cancel();

        await expectLater(
          response.stream.timeout(const Duration(seconds: 1)).toList(),
          throwsA(isA<UpdateDownloadCancelledException>()),
        );
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
        transport.close();
      }
    },
  );

  test(
    'keeps package hash verification and safe extraction after download',
    () async {
      final artifact = _zipArtifact();
      server = await _serve((request) async {
        try {
          request.response.contentLength = artifact.length;
          request.response.add(artifact);
          await request.response.close();
        } on Object {
          // The client owns response cleanup if the test fails early.
        }
      });
      final descriptor = _descriptor(
        artifactUrl: _serverUri(server!),
        artifactLength: artifact.length,
        artifactSha256: crypto.sha256.convert(artifact).toString(),
      );
      final transport = BoundedUpdateTransport(
        maxBytes: artifact.length,
        timeout: const Duration(seconds: 1),
      );

      UpdateStageResult? result;
      try {
        result = await http.runWithClient(
          () => DesktopUpdater().downloadZipFirstUpdate(
            appArchiveUrl: Uri.parse('https://updates.example.test/archive'),
            currentVersion: DesktopVersionInfo.parse('1.0.0'),
            descriptor: descriptor,
          ),
          () => transport,
        );
        expect(
          File(path.join(result!.stagingPath, 'app.txt')).readAsStringSync(),
          'version=2.0.0',
        );
      } finally {
        transport.close();
        final stagingPath = result?.stagingPath;
        if (stagingPath != null) {
          final staging = Directory(stagingPath);
          if (staging.existsSync()) {
            staging.deleteSync(recursive: true);
          }
        }
      }
    },
  );

  test('does not stage an artifact when its hash is wrong', () async {
    final artifact = _zipArtifact();
    server = await _serve((request) async {
      try {
        request.response.contentLength = artifact.length;
        request.response.add(artifact);
        await request.response.close();
      } on Object {
        // The client owns response cleanup if the hash check fails.
      }
    });
    final descriptor = _descriptor(
      artifactUrl: _serverUri(server!),
      artifactLength: artifact.length,
      artifactSha256: List<String>.filled(64, '0').join(),
    );
    final transport = BoundedUpdateTransport(
      maxBytes: artifact.length,
      timeout: const Duration(seconds: 1),
    );

    final before = _stagingDirectories();
    try {
      await expectLater(
        http.runWithClient(
          () => DesktopUpdater().downloadZipFirstUpdate(
            appArchiveUrl: Uri.parse('https://updates.example.test/archive'),
            currentVersion: DesktopVersionInfo.parse('1.0.0'),
            descriptor: descriptor,
          ),
          () => transport,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(_stagingDirectories(), unorderedEquals(before));
    } finally {
      transport.close();
    }
  });
}

Set<String> _stagingDirectories() {
  return Directory.systemTemp
      .listSync()
      .whereType<Directory>()
      .map((directory) => path.basename(directory.path))
      .where((name) => name.startsWith('desktop_updater_stage_'))
      .toSet();
}

Future<void> _download(http.Client client, Uri source, File destination) async {
  final response = await client.send(http.Request('GET', source));
  try {
    await response.stream.pipe(destination.openWrite());
  } catch (_) {
    if (destination.existsSync()) {
      destination.deleteSync();
    }
    rethrow;
  }
}

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    unawaited(_handleRequest(handler, request));
  });
  return server;
}

Future<void> _handleRequest(
  Future<void> Function(HttpRequest request) handler,
  HttpRequest request,
) async {
  try {
    await handler(request);
  } on Object {
    // Test handlers intentionally hold or close sockets while the client is
    // exercising cancellation and timeout cleanup.
  }
}

Uri _serverUri(HttpServer server) {
  return Uri.parse('http://127.0.0.1:${server.port}/artifact.zip');
}

List<int> _zipArtifact() {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'app.txt',
        utf8.encode('version=2.0.0').length,
        utf8.encode('version=2.0.0'),
      ),
    );
  return ZipEncoder().encode(archive);
}

ReleaseDescriptor _descriptor({
  required Uri artifactUrl,
  required int artifactLength,
  required String artifactSha256,
}) {
  return ReleaseDescriptor.fromJson({
    'schemaVersion': 3,
    'packageId': 'dev.leynier.alera',
    'appName': 'Alera',
    'version': '2.0.0',
    'buildNumber': 2,
    'platform': 'linux',
    'channel': 'stable',
    'artifact': <String, dynamic>{
      'kind': 'zip',
      'url': artifactUrl.toString(),
      'sha256': artifactSha256,
      'length': artifactLength,
    },
    'install': <String, dynamic>{'strategy': 'wholeDirectoryReplace'},
    'minimumUpdaterVersion': '2.5.0',
    'generatedAt': '2026-07-27T00:00:00.000Z',
  });
}
