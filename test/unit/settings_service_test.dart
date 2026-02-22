import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fakes.dart';

void main() {
  group('SettingsService', () {
    test('loads default model when nothing is persisted', () async {
      final store = InMemoryStringStore();
      final service = SettingsService(store);

      final snapshot = await service.load();

      expect(snapshot.selectedModel, codexDefaultModelId());
      expect(snapshot.selectedReasoningEffort, codexDefaultReasoningEffort());
    });

    test('migrates from legacy executor model key', () async {
      final store = InMemoryStringStore();
      await store.setString('settings.model.executor', 'gpt-5.1-codex-mini');
      final service = SettingsService(store);

      final snapshot = await service.load();

      expect(snapshot.selectedModel, 'gpt-5.1-codex-mini');
      expect(snapshot.selectedReasoningEffort, codexDefaultReasoningEffort());
    });

    test('persists selected model and reads it back', () async {
      final store = InMemoryStringStore();
      final service = SettingsService(store);

      await service.save(
        const SettingsSnapshot(
          selectedModel: 'gpt-5.2',
          selectedReasoningEffort: 'xhigh',
        ),
      );
      final snapshot = await service.load();

      expect(snapshot.selectedModel, 'gpt-5.2');
      expect(snapshot.selectedReasoningEffort, 'xhigh');
    });
  });
}
