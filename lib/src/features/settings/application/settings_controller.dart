import 'dart:async';

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
      state.copyWith(
        general: state.general.copyWith(workspaceDirectory: path),
      ),
    );
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
