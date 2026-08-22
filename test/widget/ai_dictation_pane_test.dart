import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_dictation_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows byte progress and cancellation while downloading', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download').first);
    await tester.pump();

    expect(store.downloadCount, 1);
    expect(find.text('Cancel Download'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('of'), findsWidgets);
  });

  testWidgets('download remains owned after the pane is closed', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download').first);
    await tester.pump();
    await _closePane(tester, store);
    store.completeDownload();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('queues another model while one download is active', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download').first);
    await tester.pump();
    await tester.tap(find.text('Queue Download').first);
    await tester.pump();

    expect(store.downloadCount, 1);
    expect(find.textContaining('Queued. This download starts'), findsOneWidget);
    expect(find.text('Cancel Download'), findsNWidgets(2));
  });

  testWidgets('completed model is retained with management actions', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download').first);
    await tester.pump();
    store.completeDownload();
    await tester.pumpAndSettle();

    expect(find.text('Remove Model'), findsOneWidget);
    expect(find.text('Use Model'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPane(WidgetTester tester, AiDictationModelStore store) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [aiDictationModelStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 1200,
            child: AiDictationSettingsPane(
              settings: AiDictationSettings.defaults,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _closePane(
  WidgetTester tester,
  AiDictationModelStore store,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [aiDictationModelStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
}

class _FakeAiDictationModelStore implements AiDictationModelStore {
  final Completer<String> _download = Completer<String>();
  final Set<String> _installed = <String>{};
  String? _downloadingId;
  int downloadCount = 0;

  void completeDownload() {
    _installed.add(_downloadingId!);
    _download.complete('model.bin');
  }

  @override
  AiDictationModel modelFor(String id) {
    final normalized = AiDictationModelStore.modelForId(id);
    return AiDictationModelStore.models.firstWhere(
      (model) => model.id == normalized,
    );
  }

  @override
  int downloadSizeBytes(String id) => modelFor(id).sizeBytes;

  @override
  Future<bool> isInstalled([String? id]) async => _installed.contains(
    AiDictationModelStore.modelForId(id ?? 'whisper-base'),
  );

  @override
  Future<String> download({
    String? id,
    void Function(double progress)? onProgress,
  }) {
    downloadCount++;
    _downloadingId = AiDictationModelStore.modelForId(id ?? 'whisper-base');
    onProgress?.call(0.5);
    return _download.future;
  }

  @override
  Future<void> remove([String? id]) async {
    _installed.remove(AiDictationModelStore.modelForId(id ?? 'whisper-base'));
  }

  @override
  Future<String> modelPath([String? id]) async => 'model.bin';

  @override
  Future<String> partialPath([String? id]) async => 'model.bin.part';

  @override
  Future<String> resumeIntentPath([String? id]) async => 'model.resume.json';

  @override
  Future<int> partialBytes([String? id]) async =>
      _downloadingId == AiDictationModelStore.modelForId(id ?? '') ? 1 : 0;

  @override
  Future<List<String>> resumeIntentIds() async => const <String>[];

  @override
  Future<void> cancelDownload([String? id]) async {}

  @override
  void dispose() {}
}
