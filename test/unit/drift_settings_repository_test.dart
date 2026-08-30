import 'dart:convert';

import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftSettingsRepository', () {
    test('loads defaults when no settings are stored', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);

      final settings = await repository.load();

      expect(settings.terminal.fontSize, TerminalSettings.defaults.fontSize);
    });

    test('saves and loads settings', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);
      const settings = AleraSettings(
        general: GeneralSettings(workspaceDirectory: '/workspace/alera-test'),
        terminal: TerminalSettings(
          fontFamily: 'Menlo',
          fontSize: 16,
          fontWeight: 500,
          lineHeight: 1.2,
          paddingX: 10,
          paddingY: 6,
          cursorShape: .underline,
          cursorBlink: true,
          cursorOpacity: 0.8,
          themeName: TerminalThemeNames.ghosttyDark,
          backgroundOpacity: 0.95,
          colorOverrides: TerminalColorOverrides(cursor: '#abcdef'),
          scrollbackLines: 25000,
          hostEmptyShutdownDelaySeconds: 15,
          hostDetachedSessionShutdownDelaySeconds: 90,
          hostScrollbackBytes: 32 * 1000 * 1000,
        ),
        keyboard: KeyboardShortcutSettings(
          terminalPolicy: .terminalFirst,
          overrides: <KeyboardActionId, List<String>>{
            KeyboardActionId.newTerminalTab: <String>['Mod+Shift+T'],
          },
        ),
      );

      await repository.save(settings);
      final restored = await repository.load();

      expect(restored.terminal.fontFamily, 'Menlo');
      expect(restored.terminal.fontWeight, 500);
      expect(restored.terminal.paddingX, 10);
      expect(restored.terminal.paddingY, 6);
      expect(restored.terminal.cursorShape, TerminalCursorShape.underline);
      expect(restored.terminal.cursorBlink, isTrue);
      expect(restored.terminal.cursorOpacity, 0.8);
      expect(restored.terminal.themeName, TerminalThemeNames.ghosttyDark);
      expect(restored.terminal.backgroundOpacity, 0.95);
      expect(restored.terminal.colorOverrides.cursor, '#abcdef');
      expect(restored.terminal.scrollbackLines, 25000);
      expect(restored.terminal.hostEmptyShutdownDelaySeconds, 15);
      expect(restored.terminal.hostDetachedSessionShutdownDelaySeconds, 90);
      expect(restored.terminal.hostScrollbackBytes, 32 * 1000 * 1000);
      expect(
        restored.keyboard.terminalPolicy,
        TerminalShortcutPolicy.terminalFirst,
      );
      expect(
        restored.keyboard.overrides[KeyboardActionId.newTerminalTab],
        <String>['Mod+Shift+T'],
      );
    });

    test('falls back to defaults for corrupt records', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.appSettingsTable)
          .insert(
            AppSettingsTableCompanion.insert(
              id: const Value(1),
              dataJson: jsonEncode(<String, Object?>{
                'terminal': <String, Object?>{'fontSize': <Object?>[]},
              }),
            ),
          );
      final repository = DriftSettingsRepository(db);

      final restored = await repository.load();

      expect(restored.terminal.fontSize, TerminalSettings.defaults.fontSize);
    });
  });
}
