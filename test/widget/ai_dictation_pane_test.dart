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
  testWidgets('download finishing after the pane is closed does not throw', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download Model'));
    await tester.pump();
    expect(store.downloadCount, 1);

    await _closePane(tester, store);
    store.completeDownload();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('removal finishing after the pane is closed does not throw', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore(installed: true);
    await _pumpPane(tester, store);

    await tester.tap(find.text('Remove Model'));
    await tester.pump();
    expect(store.removeCount, 1);

    await _closePane(tester, store);
    store.completeRemove();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('download finishing while mounted refreshes the model status', (
    tester,
  ) async {
    final store = _FakeAiDictationModelStore();
    await _pumpPane(tester, store);

    await tester.tap(find.text('Download Model'));
    await tester.pump();
    store.completeDownload();
    await tester.pumpAndSettle();

    expect(find.text('Remove Model'), findsOneWidget);
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
            height: 1000,
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

/// Replaces the pane the way closing the settings dialog does, so the pending
/// model work completes against an unmounted element.
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
  _FakeAiDictationModelStore({this.installed = false});

  final Completer<String> _download = Completer<String>();
  final Completer<void> _remove = Completer<void>();

  bool installed;
  int downloadCount = 0;
  int removeCount = 0;

  void completeDownload() {
    installed = true;
    _download.complete('ggml-base.bin');
  }

  void completeRemove() {
    installed = false;
    _remove.complete();
  }

  @override
  AiDictationModel modelFor(String id) => AiDictationModelStore.models.first;

  @override
  Future<bool> isInstalled([String? id]) async => installed;

  @override
  Future<String> download({
    String? id,
    void Function(double progress)? onProgress,
  }) {
    downloadCount++;
    return _download.future;
  }

  @override
  Future<void> remove([String? id]) {
    removeCount++;
    return _remove.future;
  }

  @override
  Future<String> modelPath([String? id]) async => 'ggml-base.bin';

  @override
  void dispose() {}
}
