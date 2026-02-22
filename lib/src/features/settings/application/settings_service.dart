import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.selectedModel,
    required this.selectedReasoningEffort,
  });

  final String selectedModel;
  final String selectedReasoningEffort;
}

class SettingsService {
  SettingsService(this._preferencesStore);

  final StringStore _preferencesStore;

  static const String _selectedModelKey = 'settings.model.selected';
  static const String _legacyExecutorModelKey = 'settings.model.executor';
  static const String _selectedReasoningEffortKey =
      'settings.reasoning.effort.selected';

  Future<SettingsSnapshot> load() async {
    final selected = await _preferencesStore.getString(_selectedModelKey);
    final selectedReasoningEffort = await _preferencesStore.getString(
      _selectedReasoningEffortKey,
    );
    final normalizedReasoningEffort =
        codexReasoningEffortExists(selectedReasoningEffort ?? '')
        ? selectedReasoningEffort!
        : codexDefaultReasoningEffort();

    if (selected != null && codexModelExists(selected)) {
      return SettingsSnapshot(
        selectedModel: selected,
        selectedReasoningEffort: normalizedReasoningEffort,
      );
    }

    final legacyExecutor = await _preferencesStore.getString(
      _legacyExecutorModelKey,
    );
    if (legacyExecutor != null && codexModelExists(legacyExecutor)) {
      return SettingsSnapshot(
        selectedModel: legacyExecutor,
        selectedReasoningEffort: normalizedReasoningEffort,
      );
    }

    return SettingsSnapshot(
      selectedModel: codexDefaultModelId(),
      selectedReasoningEffort: normalizedReasoningEffort,
    );
  }

  Future<void> save(SettingsSnapshot snapshot) async {
    final normalized = codexModelExists(snapshot.selectedModel)
        ? snapshot.selectedModel
        : codexDefaultModelId();
    final normalizedReasoningEffort =
        codexReasoningEffortExists(snapshot.selectedReasoningEffort)
        ? snapshot.selectedReasoningEffort
        : codexDefaultReasoningEffort();
    await _preferencesStore.setString(_selectedModelKey, normalized);
    await _preferencesStore.setString(
      _selectedReasoningEffortKey,
      normalizedReasoningEffort,
    );
  }
}
