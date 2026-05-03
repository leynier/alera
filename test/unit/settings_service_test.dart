import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
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
      expect(snapshot.selectedSpeedMode, codexDefaultSpeedMode());
      expect(snapshot.markdownEnabled, isTrue);
      expect(snapshot.planModeEnabled, isFalse);
      expect(snapshot.permissionMode, PermissionMode.defaultMode);
    });

    test('migrates from legacy executor model key', () async {
      final store = InMemoryStringStore();
      await store.setString('settings.model.executor', 'gpt-5.1-codex-mini');
      final service = SettingsService(store);

      final snapshot = await service.load();

      expect(snapshot.selectedModel, 'gpt-5.1-codex-mini');
      expect(snapshot.selectedReasoningEffort, codexDefaultReasoningEffort());
      expect(snapshot.selectedSpeedMode, codexDefaultSpeedMode());
      expect(snapshot.markdownEnabled, isTrue);
      expect(snapshot.planModeEnabled, isFalse);
      expect(snapshot.permissionMode, PermissionMode.defaultMode);
    });

    test('persists selected model and reads it back', () async {
      final store = InMemoryStringStore();
      final service = SettingsService(store);

      await service.save(
        const SettingsSnapshot(
          selectedModel: 'gpt-5.5',
          selectedReasoningEffort: 'xhigh',
          selectedSpeedMode: 'fast',
          markdownEnabled: false,
        ),
      );
      final snapshot = await service.load();

      expect(snapshot.selectedModel, 'gpt-5.5');
      expect(snapshot.selectedReasoningEffort, 'xhigh');
      expect(snapshot.selectedSpeedMode, 'fast');
      expect(snapshot.markdownEnabled, isFalse);
    });

    test('normalizes unsupported fast mode to normal', () async {
      final store = InMemoryStringStore();
      final service = SettingsService(store);

      await service.save(
        const SettingsSnapshot(
          selectedModel: 'gpt-5.3-codex',
          selectedReasoningEffort: 'high',
          selectedSpeedMode: 'fast',
          markdownEnabled: true,
        ),
      );

      final snapshot = await service.load();

      expect(snapshot.selectedModel, 'gpt-5.3-codex');
      expect(snapshot.selectedSpeedMode, 'normal');
    });

    test('persists plan mode and approval mode round trip', () async {
      final store = InMemoryStringStore();
      final service = SettingsService(store);

      await service.save(
        const SettingsSnapshot(
          selectedModel: 'gpt-5.3-codex',
          selectedReasoningEffort: 'high',
          selectedSpeedMode: 'normal',
          markdownEnabled: true,
          planModeEnabled: true,
          permissionMode: PermissionMode.fullAccess,
        ),
      );
      final snapshot = await service.load();

      expect(snapshot.planModeEnabled, isTrue);
      expect(snapshot.permissionMode, PermissionMode.fullAccess);
    });

    test('maps unknown approval mode wire value to default', () async {
      final store = InMemoryStringStore();
      await store.setString('settings.approval.mode', 'bogus');
      final service = SettingsService(store);

      final snapshot = await service.load();

      expect(snapshot.permissionMode, PermissionMode.defaultMode);
    });
  });
}
