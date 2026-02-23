import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.selectedModel,
    required this.selectedReasoningEffort,
    required this.markdownEnabled,
  });

  final String selectedModel;
  final String selectedReasoningEffort;
  final bool markdownEnabled;
}

class SettingsService {
  SettingsService(this._preferencesStore);

  final StringStore _preferencesStore;

  static const String _selectedModelKey = 'settings.model.selected';
  static const String _legacyExecutorModelKey = 'settings.model.executor';
  static const String _selectedReasoningEffortKey =
      'settings.reasoning.effort.selected';
  static const String _markdownEnabledKey = 'settings.markdown.enabled';

  Future<SettingsSnapshot> load() async {
    final selected = await _preferencesStore.getString(_selectedModelKey);
    final selectedReasoningEffort = await _preferencesStore.getString(
      _selectedReasoningEffortKey,
    );
    final markdownEnabledRaw = await _preferencesStore.getString(
      _markdownEnabledKey,
    );
    final normalizedReasoningEffort =
        codexReasoningEffortExists(selectedReasoningEffort ?? '')
        ? selectedReasoningEffort!
        : codexDefaultReasoningEffort();
    final markdownEnabled = _parseBoolOrDefault(markdownEnabledRaw, true);

    if (selected != null && codexModelExists(selected)) {
      return SettingsSnapshot(
        selectedModel: selected,
        selectedReasoningEffort: normalizedReasoningEffort,
        markdownEnabled: markdownEnabled,
      );
    }

    final legacyExecutor = await _preferencesStore.getString(
      _legacyExecutorModelKey,
    );
    if (legacyExecutor != null && codexModelExists(legacyExecutor)) {
      return SettingsSnapshot(
        selectedModel: legacyExecutor,
        selectedReasoningEffort: normalizedReasoningEffort,
        markdownEnabled: markdownEnabled,
      );
    }

    return SettingsSnapshot(
      selectedModel: codexDefaultModelId(),
      selectedReasoningEffort: normalizedReasoningEffort,
      markdownEnabled: markdownEnabled,
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
    await _preferencesStore.setString(
      _markdownEnabledKey,
      snapshot.markdownEnabled ? 'true' : 'false',
    );
  }

  bool _parseBoolOrDefault(String? raw, bool fallback) {
    if (raw == null) {
      return fallback;
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
    return fallback;
  }
}
