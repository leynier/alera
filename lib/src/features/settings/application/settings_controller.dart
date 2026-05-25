import 'dart:async';

import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:flutter_riverpod/legacy.dart';

class SettingsController extends StateNotifier<AleraSettings> {
  SettingsController(this._repository, {bool loadOnCreate = true})
    : super(AleraSettings.defaults) {
    if (loadOnCreate) {
      unawaited(load());
    }
  }

  final SettingsRepository _repository;

  Future<void> load() async {
    state = await _repository.load();
  }

  Future<void> updateTerminal(TerminalSettings settings) async {
    await _save(state.copyWith(terminal: settings));
  }

  Future<void> resetTerminalSettings() async {
    await _save(state.copyWith(terminal: TerminalSettings.defaults));
  }

  Future<void> updateWorkspaceDirectory(String? path) async {
    await _save(
      state.copyWith(general: state.general.copyWith(workspaceDirectory: path)),
    );
  }

  /// Sets the bindings for [id]. A null [chords] restores the default; an empty
  /// list disables the action.
  Future<void> setActionBindings(
    KeyboardActionId id,
    List<String>? chords,
  ) async {
    await _save(
      state.copyWith(keyboard: state.keyboard.copyWithOverride(id, chords)),
    );
  }

  /// Applies several binding changes atomically (used for conflict reassignment,
  /// where one action gains a chord and another loses it). A null value
  /// restores the default for that action.
  Future<void> applyBindingChanges(
    Map<KeyboardActionId, List<String>?> changes,
  ) async {
    var keyboard = state.keyboard;
    for (final entry in changes.entries) {
      keyboard = keyboard.copyWithOverride(entry.key, entry.value);
    }
    await _save(state.copyWith(keyboard: keyboard));
  }

  Future<void> setTerminalShortcutPolicy(TerminalShortcutPolicy policy) async {
    if (state.keyboard.terminalPolicy == policy) {
      return;
    }
    await _save(state.copyWith(keyboard: state.keyboard.copyWithPolicy(policy)));
  }

  Future<void> resetKeyboardShortcuts() async {
    await _save(state.copyWith(keyboard: state.keyboard.cleared()));
  }

  Future<void> markStarClicked() async {
    if (state.general.starClicked) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(starClicked: true)),
    );
  }

  Future<void> _save(AleraSettings settings) async {
    state = settings;
    await _repository.save(settings);
  }
}
