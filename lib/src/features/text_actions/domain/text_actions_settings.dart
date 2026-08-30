import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'text_actions_settings.mapper.dart';

/// A user-authored instruction that can replace the current text selection.
@MappableClass()
class const TextAction({
  required this.id,
  required this.name,
  required this.prompt,
  this.enabled = true,
  this.agentOverride,
  this.modelOverride,
  this.reasoningByModel = const <String, String>{},
}) with TextActionMappable {
  final String id;
  final String name;
  final String prompt;
  final bool enabled;
  final AiAssistAgent? agentOverride;
  final String? modelOverride;
  final Map<String, String> reasoningByModel;

  bool get inheritsAgent => agentOverride == null;

  bool get inheritsModel => modelOverride?.trim().isNotEmpty != true;

  AiAssistAgent effectiveAgent(AiAssistSettings settings) {
    return agentOverride ?? settings.agent;
  }

  String? effectiveModel(AiAssistSettings settings) {
    final override = modelOverride?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return settings.modelFor(effectiveAgent(settings));
  }

  String? reasoningFor(AiAssistSettings settings, {required String? model}) {
    final modelId = model?.trim();
    if (modelId == null || modelId.isEmpty) {
      return null;
    }
    final actionValue = reasoningByModel[modelId]?.trim();
    if (actionValue != null && actionValue.isNotEmpty) {
      return actionValue;
    }
    return settings.thinkingForModel(modelId);
  }

  factory fromJson(Map<String, Object?> json) =>
      TextActionMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class const TextActionsSettings({this.actions = const <TextAction>[]})
    with TextActionsSettingsMappable {
  final List<TextAction> actions;

  List<TextAction> get enabledActions =>
      actions.where((action) => action.enabled).toList(growable: false);

  static const TextActionsSettings defaults = TextActionsSettings();

  factory fromJson(Map<String, Object?> json) =>
      TextActionsSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

String? textActionValidationError(
  TextAction action,
  Iterable<TextAction> existing, {
  String? editingId,
}) {
  final id = action.id.trim();
  if (id.isEmpty) {
    return 'Action ID is required.';
  }
  final name = action.name.trim();
  if (name.isEmpty) {
    return 'Action name is required.';
  }
  if (action.prompt.trim().isEmpty) {
    return 'Action prompt is required.';
  }
  final duplicateId = existing.any(
    (candidate) => candidate.id != editingId && candidate.id.trim() == id,
  );
  if (duplicateId) {
    return 'Action IDs must be unique.';
  }
  final normalizedName = name.toLowerCase();
  final duplicate = existing.any(
    (candidate) =>
        candidate.id != editingId &&
        candidate.name.trim().toLowerCase() == normalizedName,
  );
  if (duplicate) {
    return 'Action names must be unique.';
  }
  return null;
}
