import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class SettingsSnapshot {
  const SettingsSnapshot({
    required this.selectedModel,
    required this.selectedReasoningEffort,
    required this.selectedSpeedMode,
    required this.markdownEnabled,
    this.planModeEnabled = false,
    this.permissionMode = PermissionMode.defaultMode,
  });

  final String selectedModel;
  final String selectedReasoningEffort;
  final String selectedSpeedMode;
  final bool markdownEnabled;
  final bool planModeEnabled;
  final PermissionMode permissionMode;
}

class SettingsService {
  SettingsService(this._preferencesStore);

  final StringStore _preferencesStore;

  static const String _selectedModelKey = 'settings.model.selected';
  static const String _legacyExecutorModelKey = 'settings.model.executor';
  static const String _selectedReasoningEffortKey =
      'settings.reasoning.effort.selected';
  static const String _selectedSpeedModeKey = 'settings.speed.mode.selected';
  static const String _markdownEnabledKey = 'settings.markdown.enabled';
  static const String _planModeEnabledKey = 'settings.plan.mode.enabled';
  static const String _permissionModeKey = 'settings.approval.mode';

  Future<SettingsSnapshot> load() async {
    final selected = await _preferencesStore.getString(_selectedModelKey);
    final selectedReasoningEffort = await _preferencesStore.getString(
      _selectedReasoningEffortKey,
    );
    final selectedSpeedMode = await _preferencesStore.getString(
      _selectedSpeedModeKey,
    );
    final markdownEnabledRaw = await _preferencesStore.getString(
      _markdownEnabledKey,
    );
    final planModeEnabledRaw = await _preferencesStore.getString(
      _planModeEnabledKey,
    );
    final permissionModeRaw = await _preferencesStore.getString(
      _permissionModeKey,
    );
    final normalizedReasoningEffort =
        codexReasoningEffortExists(selectedReasoningEffort ?? '')
        ? selectedReasoningEffort!
        : codexDefaultReasoningEffort();
    final normalizedSpeedMode = codexSpeedModeExists(selectedSpeedMode ?? '')
        ? selectedSpeedMode!
        : codexDefaultSpeedMode();
    final markdownEnabled = _parseBoolOrDefault(markdownEnabledRaw, true);
    final planModeEnabled = _parseBoolOrDefault(planModeEnabledRaw, false);
    final permissionMode = _parsePermissionMode(permissionModeRaw);

    if (selected != null && codexModelExists(selected)) {
      return SettingsSnapshot(
        selectedModel: selected,
        selectedReasoningEffort: normalizedReasoningEffort,
        selectedSpeedMode: closestSupportedSpeedMode(
          modelId: selected,
          speedMode: normalizedSpeedMode,
        ),
        markdownEnabled: markdownEnabled,
        planModeEnabled: planModeEnabled,
        permissionMode: permissionMode,
      );
    }

    final legacyExecutor = await _preferencesStore.getString(
      _legacyExecutorModelKey,
    );
    if (legacyExecutor != null && codexModelExists(legacyExecutor)) {
      return SettingsSnapshot(
        selectedModel: legacyExecutor,
        selectedReasoningEffort: normalizedReasoningEffort,
        selectedSpeedMode: closestSupportedSpeedMode(
          modelId: legacyExecutor,
          speedMode: normalizedSpeedMode,
        ),
        markdownEnabled: markdownEnabled,
        planModeEnabled: planModeEnabled,
        permissionMode: permissionMode,
      );
    }

    final defaultModel = codexDefaultModelId();
    return SettingsSnapshot(
      selectedModel: defaultModel,
      selectedReasoningEffort: normalizedReasoningEffort,
      selectedSpeedMode: closestSupportedSpeedMode(
        modelId: defaultModel,
        speedMode: normalizedSpeedMode,
      ),
      markdownEnabled: markdownEnabled,
      planModeEnabled: planModeEnabled,
      permissionMode: permissionMode,
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
    final normalizedSpeedMode = closestSupportedSpeedMode(
      modelId: normalized,
      speedMode: snapshot.selectedSpeedMode,
    );
    await _preferencesStore.setString(_selectedModelKey, normalized);
    await _preferencesStore.setString(
      _selectedReasoningEffortKey,
      normalizedReasoningEffort,
    );
    await _preferencesStore.setString(
      _selectedSpeedModeKey,
      normalizedSpeedMode,
    );
    await _preferencesStore.setString(
      _markdownEnabledKey,
      snapshot.markdownEnabled ? 'true' : 'false',
    );
    await _preferencesStore.setString(
      _planModeEnabledKey,
      snapshot.planModeEnabled ? 'true' : 'false',
    );
    await _preferencesStore.setString(
      _permissionModeKey,
      _permissionModeStorageValue(snapshot.permissionMode),
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

  PermissionMode _parsePermissionMode(String? raw) {
    if (raw == null) {
      return PermissionMode.defaultMode;
    }
    switch (raw.trim().toLowerCase()) {
      case 'full_access':
        return PermissionMode.fullAccess;
      default:
        return PermissionMode.defaultMode;
    }
  }

  String _permissionModeStorageValue(PermissionMode mode) {
    switch (mode) {
      case PermissionMode.fullAccess:
        return 'full_access';
      case PermissionMode.defaultMode:
        return 'default';
    }
  }
}
