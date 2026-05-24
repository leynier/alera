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
  });
}
