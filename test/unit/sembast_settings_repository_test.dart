import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/settings/infra/sembast_settings_repository.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('SembastSettingsRepository', () {
    test('loads defaults when no settings are stored', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-empty.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);

      final settings = await repository.load();

      expect(settings.terminal.fontSize, TerminalSettings.defaults.fontSize);
    });

    test('saves and loads settings', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-save.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);
      const settings = AleraSettings(
        general: GeneralSettings(workspaceDirectory: '/tmp/alera-test'),
        terminal: TerminalSettings(
          fontFamily: 'Menlo',
          fontSize: 16,
          fontWeight: 500,
          lineHeight: 1.2,
          paddingX: 10,
          paddingY: 6,
          cursorShape: TerminalCursorShape.underline,
          cursorBlink: true,
          cursorOpacity: 0.8,
          themeName: TerminalThemeNames.ghosttyDark,
          backgroundOpacity: 0.95,
          colorOverrides: TerminalColorOverrides(cursor: '#abcdef'),
          scrollbackLines: 25000,
        ),
        keyboard: KeyboardShortcutSettings(
          terminalPolicy: TerminalShortcutPolicy.terminalFirst,
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
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-corrupt.db',
      );
      addTearDown(db.close);
      await AleraStores.settings.record('settings').put(db, <String, Object?>{
        'terminal': <String, Object?>{'fontSize': <Object?>[]},
      });
      final repository = SembastSettingsRepository(db);

      final restored = await repository.load();

      expect(restored.terminal.fontSize, TerminalSettings.defaults.fontSize);
    });
  });
}
