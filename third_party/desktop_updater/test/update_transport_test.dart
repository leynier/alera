import "dart:async";
import "dart:convert";
import "dart:io";

import "package:desktop_updater/src/core/update_cancellation.dart";
import "package:desktop_updater/src/core/update_retry_policy.dart";
import "package:desktop_updater/src/io/composite_update_transport.dart";
import "package:desktop_updater/src/io/file_update_transport.dart";
import "package:desktop_updater/src/io/http_update_transport.dart";
import "package:flutter_test/flutter_test.dart";
import "package:http/http.dart" as http;
import "package:http/testing.dart";
import "package:path/path.dart" as path;

void main() {
  test("file transport copies exact file URLs with progress", () async {
    final tempDir = await Directory.systemTemp.createTemp("transport_");
    try {
      final source = File(path.join(tempDir.path, "source.txt"))
        ..writeAsStringSync("hello");
      final destination = File(path.join(tempDir.path, "out", "copy.txt"));
      final progress = <int>[];

      await const FileUpdateTransport().download(
        source.uri,
        destination,
        onProgress: (receivedBytes, _) => progress.add(receivedBytes),
      );

      expect(destination.readAsStringSync(), "hello");
      expect(progress.last, 5);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("file transport rejects non-file URLs", () {
    expect(
      () => const FileUpdateTransport().download(
        Uri.parse("https://example.com/file.zip"),
        File("/tmp/file.zip"),
      ),
      throwsUnsupportedError,
    );
  });

  test("immediate composite cancellation reaches a newly registered copy",
      () async {
    final tempDir = await Directory.systemTemp.createTemp("file_transport_");
    final transport = CompositeUpdateTransport();
    try {
      final source = File(path.join(tempDir.path, "source.bin"));
      await source.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 3));
      final destination = File(path.join(tempDir.path, "copy.bin"));

      final download = transport.download(source.uri, destination);
      final cancellation = transport.cancel();

      await expectLater(
        download,
        throwsA(isA<UpdateCancelledException>()),
      );
      await cancellation;
      expect(destination.existsSync(), isFalse);
      expect(File("${destination.path}.part").existsSync(), isFalse);
    } finally {
      transport.close();
      await tempDir.delete(recursive: true);
    }
  });

  test("composite file transport cancels a large copy before rename", () async {
    final tempDir = await Directory.systemTemp.createTemp("file_transport_");
    final transport = CompositeUpdateTransport();
    try {
      final source = File(path.join(tempDir.path, "source.bin"));
      await source.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 7));
      final destination = File(path.join(tempDir.path, "out", "copy.bin"));
      final progress = <int>[];
      Future<void>? cancellation;

      final download = transport.download(
        source.uri,
        destination,
        onProgress: (receivedBytes, _) {
          progress.add(receivedBytes);
          cancellation ??= transport.cancel();
        },
      );

      await expectLater(
        download,
        throwsA(isA<UpdateCancelledException>()),
      );

      expect(progress, hasLength(1));
      expect(destination.existsSync(), isFalse);
      expect(File("${destination.path}.part").existsSync(), isFalse);

      await transport.download(source.uri, destination);
      expect(destination.lengthSync(), source.lengthSync());
    } finally {
      transport.close();
      await tempDir.delete(recursive: true);
    }
  });

  test("canceled file copy preserves destination and a later copy recovers",
      () async {
    final tempDir = await Directory.systemTemp.createTemp("file_transport_");
    final transport = CompositeUpdateTransport();
    try {
      final source = File(path.join(tempDir.path, "source.bin"));
      await source.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 9));
      final destination = File(path.join(tempDir.path, "copy.bin"));
      await destination.writeAsString("previous artifact");
      final progress = <int>[];
      Future<void>? cancellation;

      final download = transport.download(
        source.uri,
        destination,
        onProgress: (receivedBytes, _) {
          progress.add(receivedBytes);
          cancellation ??= transport.cancel();
        },
      );

      await expectLater(
        download,
        throwsA(isA<UpdateCancelledException>()),
      );

      expect(progress, hasLength(1));
      expect(destination.readAsStringSync(), "previous artifact");
      expect(
        await destination.parent
            .list()
            .where((entity) => entity.path.contains(".previous."))
            .isEmpty,
        isTrue,
      );

      final recovery = transport.download(source.uri, destination);
      await recovery;
      await cancellation;
      expect(destination.lengthSync(), source.lengthSync());
      expect(destination.readAsBytesSync().first, 9);
    } finally {
      transport.close();
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport retries transient statuses with backoff", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final delays = <Duration>[];
    var attempts = 0;
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          attempts += 1;
          if (attempts < 3) {
            return http.Response("busy", HttpStatus.serviceUnavailable);
          }
          return http.Response("ok", HttpStatus.ok);
        }),
        retryPolicy: const UpdateRetryPolicy(),
        delay: (duration) async {
          delays.add(duration);
        },
      );
      final destination = File(path.join(tempDir.path, "download.txt"));

      await transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        destination,
      );

      expect(attempts, 3);
      expect(delays, [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
      ]);
      expect(destination.readAsStringSync(), "ok");
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport does not retry non-transient statuses", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final delays = <Duration>[];
    var attempts = 0;
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          attempts += 1;
          return http.Response("missing", HttpStatus.notFound);
        }),
        delay: (duration) async {
          delays.add(duration);
        },
      );
      final destination = File(path.join(tempDir.path, "download.txt"));

      await expectLater(
        transport.download(
          Uri.parse("https://updates.example.com/download.txt"),
          destination,
        ),
        throwsA(isA<HttpException>()),
      );

      expect(attempts, 1);
      expect(delays, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport retries transient client failures", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    var attempts = 0;
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          attempts += 1;
          if (attempts == 1) {
            throw http.ClientException("connection reset", request.url);
          }
          return http.Response.bytes(utf8.encode("ok"), HttpStatus.ok);
        }),
        retryPolicy: const UpdateRetryPolicy(maxAttempts: 2),
        delay: (_) async {},
      );
      final destination = File(path.join(tempDir.path, "download.txt"));

      await transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        destination,
      );

      expect(attempts, 2);
      expect(destination.readAsStringSync(), "ok");
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport sends app-owned request headers", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    Map<String, String>? capturedHeaders;
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          capturedHeaders = Map<String, String>.of(request.headers);
          return http.Response("ok", HttpStatus.ok);
        }),
        requestHeadersProvider: (source) {
          return {
            HttpHeaders.authorizationHeader: "Bearer token",
            "x-update-host": source.host,
          };
        },
      );
      final destination = File(path.join(tempDir.path, "download.txt"));

      await transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        destination,
      );

      expect(
        capturedHeaders?[HttpHeaders.authorizationHeader],
        "Bearer token",
      );
      expect(capturedHeaders?["x-update-host"], "updates.example.com");
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport resumes existing partial with valid range response",
      () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final ranges = <String?>[];
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          ranges.add(request.headers[HttpHeaders.rangeHeader]);
          return http.Response.bytes(
            utf8.encode("world"),
            HttpStatus.partialContent,
            headers: const {
              HttpHeaders.contentRangeHeader: "bytes 6-10/11",
            },
          );
        }),
      );
      final destination = File(path.join(tempDir.path, "download.txt"));
      final partial = File("${destination.path}.part")
        ..createSync(recursive: true)
        ..writeAsStringSync("hello ");

      await transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        destination,
      );

      expect(ranges, ["bytes=6-"]);
      expect(destination.readAsStringSync(), "hello world");
      expect(partial.existsSync(), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport restarts when server ignores range request", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final ranges = <String?>[];
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          ranges.add(request.headers[HttpHeaders.rangeHeader]);
          return http.Response("fresh bytes", HttpStatus.ok);
        }),
      );
      final destination = File(path.join(tempDir.path, "download.txt"));
      final partial = File("${destination.path}.part")
        ..createSync(recursive: true)
        ..writeAsStringSync("stale");

      await transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        destination,
      );

      expect(ranges, ["bytes=5-"]);
      expect(destination.readAsStringSync(), "fresh bytes");
      expect(partial.existsSync(), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http transport deletes partial and fails on invalid content range",
      () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final ranges = <String?>[];
    try {
      final transport = HttpUpdateTransport(
        client: MockClient((request) async {
          ranges.add(request.headers[HttpHeaders.rangeHeader]);
          return http.Response.bytes(
            utf8.encode("world"),
            HttpStatus.partialContent,
            headers: const {
              HttpHeaders.contentRangeHeader: "bytes 0-4/11",
            },
          );
        }),
      );
      final destination = File(path.join(tempDir.path, "download.txt"));
      final partial = File("${destination.path}.part")
        ..createSync(recursive: true)
        ..writeAsStringSync("hello ");

      await expectLater(
        transport.download(
          Uri.parse("https://updates.example.com/download.txt"),
          destination,
        ),
        throwsA(isA<HttpException>()),
      );

      expect(ranges, ["bytes=6-"]);
      expect(partial.existsSync(), isFalse);
      expect(destination.existsSync(), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("http cancellation interrupts retry backoff", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final retryDelay = Completer<void>();
    final delayStarted = Completer<void>();
    final transport = HttpUpdateTransport(
      client: MockClient((request) async {
        throw http.ClientException("connection reset", request.url);
      }),
      retryPolicy: const UpdateRetryPolicy(maxAttempts: 2),
      delay: (_) {
        if (!delayStarted.isCompleted) {
          delayStarted.complete();
        }
        return retryDelay.future;
      },
    );
    try {
      final download = transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        File(path.join(tempDir.path, "download.txt")),
      );
      await delayStarted.future;
      await transport.cancel();

      await expectLater(
        download.timeout(const Duration(seconds: 1)),
        throwsA(isA<Exception>()),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test("composite HTTP cancellation completes after client close", () async {
    final tempDir = await Directory.systemTemp.createTemp("http_transport_");
    final body = StreamController<List<int>>();
    final client = _NeverEndingHttpClient(body.stream);
    final transport = CompositeUpdateTransport(
      httpTransport: HttpUpdateTransport(client: client),
    );
    try {
      final download = transport.download(
        Uri.parse("https://updates.example.com/download.txt"),
        File(path.join(tempDir.path, "download.txt")),
      );
      await client.requestStarted.future;

      await transport.cancel().timeout(const Duration(seconds: 1));
      expect(client.closed, isTrue);

      await body.close();
      await expectLater(download, throwsA(isA<Exception>()));
    } finally {
      if (!body.isClosed) {
        await body.close();
      }
      transport.close();
      await tempDir.delete(recursive: true);
    }
  });
}

class _NeverEndingHttpClient extends http.BaseClient {
  _NeverEndingHttpClient(this._body);

  final Stream<List<int>> _body;
  final Completer<void> requestStarted = Completer<void>();
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!requestStarted.isCompleted) {
      requestStarted.complete();
    }
    return http.StreamedResponse(
      _body,
      HttpStatus.ok,
      request: request,
    );
  }

  @override
  void close() {
    closed = true;
  }
}
