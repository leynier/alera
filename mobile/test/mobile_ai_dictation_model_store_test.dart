import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:alera_mobile/src/features/ai_dictation/infra/mobile_ai_dictation_model_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_settings_screen.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory supportDirectory;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    supportDirectory = await Directory.systemTemp.createTemp(
      'alera-mobile-model-test-',
    );
  });

  tearDown(() async {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test(
    'disposal cancels an active transfer and removes its staging file',
    () async {
      final client = _CancellableClient();
      final store = _store(client, supportDirectory, const <int>[1]);
      final download = store.download();
      await client.streamListened.future;
      client.add(const <int>[1]);
      await Future<void>.delayed(Duration.zero);

      store.dispose();

      await expectLater(
        download,
        throwsA(isA<MobileAiModelDownloadCancelled>()),
      );
      expect(await File('${await store.path()}.download').exists(), isFalse);
    },
  );

  test('an interrupted transfer cleans up and can be retried', () async {
    const bytes = <int>[1, 2, 3];
    final client = _QueuedClient(<http.StreamedResponse>[
      http.StreamedResponse(
        Stream<List<int>>.error(
          http.ClientException('Connection closed while receiving data.'),
        ),
        HttpStatus.ok,
        contentLength: bytes.length,
      ),
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        HttpStatus.ok,
        contentLength: bytes.length,
      ),
    ]);
    final store = _store(client, supportDirectory, bytes);
    addTearDown(store.dispose);

    await expectLater(
      store.download(),
      throwsA(isA<MobileAiModelDownloadException>()),
    );
    expect(await File('${await store.path()}.download').exists(), isFalse);

    final destination = await store.download();

    expect(await File(destination).readAsBytes(), bytes);
    expect(await store.isInstalled(), isTrue);
  });

  testWidgets('the settings screen offers retry after an interruption', (
    tester,
  ) async {
    final store = _RetryModelStore();
    await tester.pumpWidget(
      MaterialApp(home: MobileAiDictationSettingsScreen(modelStore: store)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pumpAndSettle();

    expect(find.text(MobileAiModelDownloadException.message), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Ready'), findsOneWidget);
    expect(find.text(MobileAiModelDownloadException.message), findsNothing);
  });
}

MobileAiDictationModelStore _store(
  http.Client client,
  Directory supportDirectory,
  List<int> expectedBytes,
) => MobileAiDictationModelStore(
  client: client,
  downloadUrl: Uri.parse('https://example.test/ggml-base.bin'),
  expectedSha256: sha256.convert(expectedBytes).toString(),
  supportDirectory: () async => supportDirectory,
);

final class _QueuedClient extends http.BaseClient {
  _QueuedClient(Iterable<http.StreamedResponse> responses)
    : _responses = Queue<http.StreamedResponse>.of(responses);

  final Queue<http.StreamedResponse> _responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _responses.removeFirst();
}

final class _CancellableClient extends http.BaseClient {
  final streamListened = Completer<void>();
  late final StreamController<List<int>> _stream = StreamController<List<int>>(
    onListen: streamListened.complete,
  );

  void add(List<int> bytes) => _stream.add(bytes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_stream.stream, HttpStatus.ok, contentLength: 2);

  @override
  void close() {
    _stream.addError(
      http.ClientException('Connection closed while receiving data.'),
    );
    unawaited(_stream.close());
  }
}

final class _RetryModelStore implements MobileAiDictationModels {
  var _attempts = 0;

  @override
  Future<String> download({void Function(double)? onProgress}) async {
    _attempts += 1;
    if (_attempts == 1) throw const MobileAiModelDownloadException();
    return 'ggml-base.bin';
  }

  @override
  Future<bool> isInstalled() async => false;

  @override
  void dispose() {}
}
