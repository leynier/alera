import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsController', () {
    test('autosaves terminal updates', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.load();

      await controller.updateTerminal(
        controller.state.terminal.copyWith(fontSize: 18),
      );
      final restored = await repository.load();

      expect(container.read(settingsControllerProvider).terminal.fontSize, 18);
      expect(restored.terminal.fontSize, 18);
    });

    test('resets terminal settings to defaults', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.load();

      await controller.updateTerminal(
        controller.state.terminal.copyWith(
          fontFamily: 'Menlo',
          cursorShape: TerminalCursorShape.bar,
        ),
      );
      await controller.resetTerminalSettings();

      expect(
        container.read(settingsControllerProvider).terminal.fontFamily,
        'JetBrains Mono',
      );
      expect(
        container.read(settingsControllerProvider).terminal.cursorShape,
        TerminalCursorShape.block,
      );
      expect((await repository.load()).terminal.fontFamily, 'JetBrains Mono');
    });

    test('persists keyboard binding changes and reset', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
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

    test(
      'persists destructive confirmation and agent status preferences',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftSettingsRepository(db);
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final controller = container.read(settingsControllerProvider.notifier);
        await controller.load();

        await controller.setConfirmProjectRemoval(false);
        await controller.setConfirmWorkspaceRemoval(false);
        await controller.setAgentStatusHookEnabled(AgentType.codex, true);
        await controller.setAgentStatusHookEnabled(AgentType.agy, true);
        await controller.setAgentStatusHookEnabled(AgentType.opencode, true);
        await controller.setAgentStatusHookEnabled(AgentType.pi, true);
        await controller.setAgentStatusHookEnabled(AgentType.amp, true);
        await controller.setAgentStatusNotificationsEnabled(true);

        final restored = await repository.load();
        expect(
          container
              .read(settingsControllerProvider)
              .general
              .confirmProjectRemoval,
          isFalse,
        );
        expect(
          container
              .read(settingsControllerProvider)
              .general
              .confirmWorkspaceRemoval,
          isFalse,
        );
        expect(restored.general.confirmProjectRemoval, isFalse);
        expect(restored.general.confirmWorkspaceRemoval, isFalse);
        expect(restored.general.agentStatusHooks.codex, isTrue);
        expect(restored.general.agentStatusHooks.claude, isFalse);
        expect(restored.general.agentStatusHooks.copilot, isFalse);
        expect(restored.general.agentStatusHooks.agy, isTrue);
        expect(restored.general.agentStatusHooks.opencode, isTrue);
        expect(restored.general.agentStatusHooks.pi, isTrue);
        expect(restored.general.agentStatusHooks.amp, isTrue);
        expect(restored.general.agentStatusNotificationsEnabled, isTrue);
      },
    );

    test('applyBindingChanges reassigns a chord atomically', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftSettingsRepository(db);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.load();

      await controller.applyBindingChanges(<KeyboardActionId, List<String>?>{
        KeyboardActionId.closeTab: <String>['Mod+T'],
        KeyboardActionId.newTerminalTab: <String>[],
      });

      final restored = await repository.load();
      expect(restored.keyboard.overrides[KeyboardActionId.closeTab], <String>[
        'Mod+T',
      ]);
      expect(
        restored.keyboard.isDisabled(KeyboardActionId.newTerminalTab),
        isTrue,
      );
    });

    test(
      'markStarClicked persists once and becomes a no-op afterward',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftSettingsRepository(db);
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final controller = container.read(settingsControllerProvider.notifier);
        await controller.load();

        await controller.markStarClicked();
        final firstRestore = await repository.load();
        expect(firstRestore.general.starClicked, isTrue);

        await controller.markStarClicked();
        final secondRestore = await repository.load();
        expect(secondRestore.general.starClicked, isTrue);
      },
    );
  });
}
