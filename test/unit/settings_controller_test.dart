import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/sembast_settings_repository.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('SettingsController', () {
    test('autosaves terminal updates', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-controller-save.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);
      final controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.updateTerminal(
        controller.state.terminal.copyWith(fontSize: 18),
      );
      final restored = await repository.load();

      expect(controller.state.terminal.fontSize, 18);
      expect(restored.terminal.fontSize, 18);
    });

    test('resets terminal settings to defaults', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-controller-reset.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);
      final controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.updateTerminal(
        controller.state.terminal.copyWith(
          fontFamily: 'Menlo',
          cursorShape: TerminalCursorShape.bar,
        ),
      );
      await controller.resetTerminalSettings();

      expect(controller.state.terminal.fontFamily, 'JetBrains Mono');
      expect(controller.state.terminal.cursorShape, TerminalCursorShape.block);
      expect((await repository.load()).terminal.fontFamily, 'JetBrains Mono');
    });

    test('persists keyboard binding changes and reset', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-controller-keyboard.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);
      final controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.setActionBindings(
        KeyboardActionId.newTerminalTab,
        <String>['Mod+Shift+T'],
      );
      await controller.setTerminalShortcutPolicy(
        TerminalShortcutPolicy.terminalFirst,
      );

      var restored = await repository.load();
      expect(
        restored.keyboard.overrides[KeyboardActionId.newTerminalTab],
        <String>['Mod+Shift+T'],
      );
      expect(
        restored.keyboard.terminalPolicy,
        TerminalShortcutPolicy.terminalFirst,
      );

      await controller.resetKeyboardShortcuts();
      restored = await repository.load();
      expect(restored.keyboard.overrides, isEmpty);
      // Reset preserves the chosen policy.
      expect(
        restored.keyboard.terminalPolicy,
        TerminalShortcutPolicy.terminalFirst,
      );
    });

    test('applyBindingChanges reassigns a chord atomically', () async {
      final db = await openAleraDb(
        factory: databaseFactoryMemory,
        path: 'settings-controller-reassign.db',
      );
      addTearDown(db.close);
      final repository = SembastSettingsRepository(db);
      final controller = SettingsController(repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.applyBindingChanges(<KeyboardActionId, List<String>?>{
        KeyboardActionId.closeTab: <String>['Mod+T'],
        KeyboardActionId.newTerminalTab: <String>[],
      });

      final restored = await repository.load();
      expect(
        restored.keyboard.overrides[KeyboardActionId.closeTab],
        <String>['Mod+T'],
      );
      expect(restored.keyboard.isDisabled(KeyboardActionId.newTerminalTab),
          isTrue);
    });
  });
}
