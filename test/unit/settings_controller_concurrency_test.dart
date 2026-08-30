import 'dart:async';
import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_mutations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedSettingsRepository implements SettingsRepository {
  var saved = AleraSettings.defaults;
  final entered = Completer<void>();
  final release = Completer<void>();
  bool failFirst = false;
  int writes = 0;
  @override
  Future<AleraSettings> load() async => saved;
  @override
  Future<void> save(AleraSettings settings) async {
    if (writes++ == 0) {
      entered.complete();
      await release.future;
      if (failFirst) throw StateError('Persistence failed');
    }
    saved = settings;
  }
}

void main() {
  test('explicit reversions preserve unrelated queued edits', () async {
    final repository = DelayedSettingsRepository();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.load();
    final initial = controller.state.terminal;
    final first = controller.updateTerminal(
      (latest) => latest.copyWith(fontSize: 20),
    );
    await repository.entered.future;
    final other = controller.updateTerminal(
      (latest) => latest.copyWith(cursorBlink: true),
    );
    final revert = controller.updateTerminal(
      (latest) => latest.copyWith(fontSize: initial.fontSize),
    );
    expect(controller.state.terminal, initial);
    repository.release.complete();
    await Future.wait([first, other, revert]);
    expect(controller.state.terminal.fontSize, initial.fontSize);
    expect(controller.state.terminal.cursorBlink, true);
    expect(repository.saved.terminal, controller.state.terminal);
  });
  test(
    'queued action additions and edits preserve other identifiers',
    () async {
      final repository = DelayedSettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.load();
      final one = TextAction(id: 'one', name: 'One', prompt: 'Prompt one');
      final two = TextAction(id: 'two', name: 'Two', prompt: 'Prompt two');
      final first = controller.updateTextActions(
        (latest) => TextActionsMutations.append(latest, one),
      );
      await repository.entered.future;
      final second = controller.updateTextActions(
        (latest) => TextActionsMutations.append(latest, two),
      );
      final edit = controller.updateTextActions(
        (latest) =>
            TextActionsMutations.update(latest, one.copyWith(enabled: false)),
      );
      final reorder = controller.updateTextActions(
        (latest) => TextActionsMutations.moveBefore(latest, 'two', 'one'),
      );
      repository.release.complete();
      await Future.wait([first, second, edit, reorder]);
      final actions = controller.state.textActions.actions;
      expect(actions.where((a) => a.id == 'one').single.enabled, false);
      expect(actions.where((a) => a.id == 'two').single.prompt, two.prompt);
      expect(
        actions.indexWhere((a) => a.id == 'two'),
        lessThan(actions.indexWhere((a) => a.id == 'one')),
      );
      expect(repository.saved.textActions, controller.state.textActions);
    },
  );
  for (final fail in [false, true]) {
    test(
      'overlapping settings compose after persistence (failure: $fail)',
      () async {
        final repository = DelayedSettingsRepository()..failFirst = fail;
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final controller = container.read(settingsControllerProvider.notifier);
        await controller.load();
        final first = controller.setShowDockBadge(false);
        final checkedFirst = fail
            ? expectLater(first, throwsStateError)
            : first;
        await repository.entered.future;
        final second = controller.setShowTrayBadge(false);
        final reload = controller.load();
        expect(
          container.read(settingsControllerProvider).general.showDockBadge,
          isTrue,
        );
        repository.release.complete();
        await Future.wait([checkedFirst, second, reload]);
        expect(repository.saved.general.showDockBadge, fail);
        expect(repository.saved.general.showTrayBadge, isFalse);
        expect(container.read(settingsControllerProvider), repository.saved);
      },
    );
  }
  for (final fail in [false, true]) {
    test(
      'overlapping terminal edits retain independent fields (failure: $fail)',
      () async {
        final repository = DelayedSettingsRepository()..failFirst = fail;
        final container = ProviderContainer(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final controller = container.read(settingsControllerProvider.notifier);
        await controller.load();
        final original = controller.state.terminal;
        final first = controller.updateTerminal(
          (terminal) => terminal.copyWith(fontSize: 20),
        );
        final checked = fail ? expectLater(first, throwsStateError) : first;
        await repository.entered.future;
        final second = controller.updateTerminal(
          (terminal) => terminal.copyWith(cursorBlink: true),
        );
        repository.release.complete();
        await Future.wait([checked, second]);
        expect(
          repository.saved.terminal.fontSize,
          fail ? original.fontSize : 20,
        );
        expect(repository.saved.terminal.cursorBlink, true);
        await controller.resetTerminalSettings();
        expect(repository.saved.terminal, AleraSettings.defaults.terminal);
      },
    );
  }
}
