import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class SettingsSnapshot {
  const SettingsSnapshot({required this.selectedModel});

  final String selectedModel;
}

class SettingsService {
  SettingsService(this._preferencesStore);

  final StringStore _preferencesStore;

  static const String _selectedModelKey = 'settings.model.selected';
  static const String _legacyExecutorModelKey = 'settings.model.executor';

  Future<SettingsSnapshot> load() async {
    final selected = await _preferencesStore.getString(_selectedModelKey);
    if (selected != null && codexModelExists(selected)) {
      return SettingsSnapshot(selectedModel: selected);
    }

    final legacyExecutor = await _preferencesStore.getString(
      _legacyExecutorModelKey,
    );
    if (legacyExecutor != null && codexModelExists(legacyExecutor)) {
      return SettingsSnapshot(selectedModel: legacyExecutor);
    }

    return SettingsSnapshot(selectedModel: codexDefaultModelId());
  }

  Future<void> save(SettingsSnapshot snapshot) async {
    final normalized = codexModelExists(snapshot.selectedModel)
        ? snapshot.selectedModel
        : codexDefaultModelId();
    await _preferencesStore.setString(_selectedModelKey, normalized);
  }
}
