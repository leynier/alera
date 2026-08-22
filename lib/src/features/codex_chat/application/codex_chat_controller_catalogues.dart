part of 'codex_chat_controller.dart';

// These extensions are split from the notifier only to keep the source files small.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _CodexChatControllerCatalogues on CodexChatController {
  Future<void> _loadCatalogues() async {
    final generation = ++_catalogueGeneration;
    final modelLoad = await _loadModels(state.models);
    final models = modelLoad.models;
    List<Map<String, Object?>> modes = const <Map<String, Object?>>[];
    List<Map<String, Object?>> skills = const <Map<String, Object?>>[];
    List<Map<String, Object?>> apps = const <Map<String, Object?>>[];
    try {
      final payload = await _host.listCollaborationModes();
      modes = _items(payload);
    } catch (_) {
      // Collaboration modes are optional on older app-server builds.
    }
    try {
      skills = _skillItems(await _host.listSkills(tabId));
    } catch (_) {
      // Skills are optional on older app-server builds.
    }
    try {
      apps = _appItems(await _host.listApps(tabId));
    } catch (_) {
      // Apps are optional on older app-server builds.
    }
    if (!ref.mounted || generation != _catalogueGeneration) return;
    final selectedModel = !modelLoad.authoritative
        ? state.selectedModel
        : models.any((model) => model.id == state.selectedModel)
        ? state.selectedModel
        : (models.where((model) => model.isDefault).firstOrNull ??
                  (models.isNotEmpty ? models.first : null))
              ?.id;
    final selectedOption = models
        .where((model) => model.id == selectedModel)
        .firstOrNull;
    final initialReasoning = state.reasoningEffort;
    state = state.copyWith(
      models: models,
      collaborationModes: modes,
      skills: skills,
      apps: apps,
      selectedModel: selectedModel,
      reasoningEffort: _supportedEffort(selectedOption, initialReasoning),
      speedMode: selectedOption?.supportsFastMode == false
          ? 'normal'
          : state.speedMode,
    );
  }
}
