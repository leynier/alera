import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'ai_text_generation_settings.mapper.dart';

@MappableEnum()
enum AiTextGenerationOperation {
  commitMessage('commitMessage'),
  pullRequestDetails('pullRequestDetails'),
  branchName('branchName'),
  readingDiff('readingDiff'),
  workspaceIdentity('workspaceIdentity'),
  speechMessage('speechMessage');

  const AiTextGenerationOperation(this.key);

  final String key;

  String get label => switch (this) {
    AiTextGenerationOperation.commitMessage => 'Commit Messages',
    AiTextGenerationOperation.pullRequestDetails => 'Pull Request Details',
    AiTextGenerationOperation.branchName => 'Branch Names',
    AiTextGenerationOperation.readingDiff => 'Reading Diffs',
    AiTextGenerationOperation.workspaceIdentity => 'Workspace Identity',
    AiTextGenerationOperation.speechMessage => 'Speech Messages',
  };
}

@MappableEnum()
enum AiTextGenerationAgent {
  codex('codex'),
  claude('claude'),
  copilot('copilot'),
  cursor('cursor'),
  agy('agy'),
  opencode('opencode'),
  opencode2('opencode2'),
  pi('pi'),
  amp('amp'),
  grok('grok'),
  fx('fx'),
  custom('custom');

  const AiTextGenerationAgent(this.key);

  final String key;

  String get label => switch (this) {
    AiTextGenerationAgent.codex => 'Codex',
    AiTextGenerationAgent.claude => 'Claude Code',
    AiTextGenerationAgent.copilot => 'GitHub Copilot',
    AiTextGenerationAgent.cursor => 'Cursor',
    AiTextGenerationAgent.agy => 'Antigravity',
    AiTextGenerationAgent.opencode => 'OpenCode',
    AiTextGenerationAgent.opencode2 => 'OpenCode 2',
    AiTextGenerationAgent.pi => 'Pi',
    AiTextGenerationAgent.amp => 'Amp',
    AiTextGenerationAgent.grok => 'Grok Build',
    AiTextGenerationAgent.fx => 'fx',
    AiTextGenerationAgent.custom => 'Custom Command',
  };

  AgentType? get agentType => switch (this) {
    AiTextGenerationAgent.codex => AgentType.codex,
    AiTextGenerationAgent.claude => AgentType.claude,
    AiTextGenerationAgent.copilot => AgentType.copilot,
    AiTextGenerationAgent.cursor => AgentType.cursor,
    AiTextGenerationAgent.agy => AgentType.agy,
    AiTextGenerationAgent.opencode => AgentType.opencode,
    AiTextGenerationAgent.opencode2 => AgentType.opencode2,
    AiTextGenerationAgent.pi => AgentType.pi,
    AiTextGenerationAgent.amp => AgentType.amp,
    AiTextGenerationAgent.grok => AgentType.grok,
    AiTextGenerationAgent.fx => AgentType.fx,
    AiTextGenerationAgent.custom => null,
  };
}

@MappableClass()
class AiTextDiscoveredThinkingLevel with AiTextDiscoveredThinkingLevelMappable {
  const AiTextDiscoveredThinkingLevel({required this.id, required this.label});

  final String id;
  final String label;
}

@MappableClass()
class AiTextDiscoveredModel with AiTextDiscoveredModelMappable {
  const AiTextDiscoveredModel({
    required this.id,
    required this.label,
    this.thinkingLevels = const <AiTextDiscoveredThinkingLevel>[],
    this.defaultThinkingLevel,
  });

  final String id;
  final String label;
  final List<AiTextDiscoveredThinkingLevel> thinkingLevels;
  final String? defaultThinkingLevel;
}

@MappableClass()
class AiTextGenerationPromptSettings
    with AiTextGenerationPromptSettingsMappable {
  const AiTextGenerationPromptSettings({this.agent, this.model});

  final AiTextGenerationAgent? agent;
  final String? model;

  bool get inheritsAgent => agent == null;

  bool get inheritsModel => model == null || model!.trim().isEmpty;
}

@MappableClass()
class AiTextGenerationSettings with AiTextGenerationSettingsMappable {
  const AiTextGenerationSettings({
    this.enabled = true,
    this.agent = AiTextGenerationAgent.codex,
    this.selectedModelByAgent = const <AiTextGenerationAgent, String>{},
    this.selectedThinkingByModel = const <String, String>{},
    this.selectedThinkingByOperation =
        const <AiTextGenerationOperation, Map<String, String>>{},
    this.discoveredModelsByAgent =
        const <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{},
    this.discoveredDefaultModelByAgent =
        const <AiTextGenerationAgent, String>{},
    this.customCommand = '',
    this.instructionsByOperation = const <AiTextGenerationOperation, String>{},
    this.promptSettingsByOperation =
        const <AiTextGenerationOperation, AiTextGenerationPromptSettings>{},
    this.timeoutSeconds = 120,
  });

  final bool enabled;
  final AiTextGenerationAgent agent;
  final Map<AiTextGenerationAgent, String> selectedModelByAgent;
  final Map<String, String> selectedThinkingByModel;
  final Map<AiTextGenerationOperation, Map<String, String>>
  selectedThinkingByOperation;
  final Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>
  discoveredModelsByAgent;
  final Map<AiTextGenerationAgent, String> discoveredDefaultModelByAgent;
  final String customCommand;
  final Map<AiTextGenerationOperation, String> instructionsByOperation;
  final Map<AiTextGenerationOperation, AiTextGenerationPromptSettings>
  promptSettingsByOperation;
  final int timeoutSeconds;

  String? modelFor(AiTextGenerationAgent agent) {
    final value = selectedModelByAgent[agent]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? thinkingForModel(String? model) {
    if (model == null || model.trim().isEmpty) {
      return null;
    }
    final value = selectedThinkingByModel[model]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? thinkingForOperation(
    AiTextGenerationOperation operation,
    String? model,
  ) {
    if (model == null || model.trim().isEmpty) {
      return null;
    }
    final operationValue = selectedThinkingByOperation[operation]?[model]
        ?.trim();
    if (operationValue != null && operationValue.isNotEmpty) {
      return operationValue;
    }
    return thinkingForModel(model);
  }

  String instructionsFor(AiTextGenerationOperation operation) {
    return instructionsByOperation[operation]?.trim() ?? '';
  }

  AiTextGenerationPromptSettings promptSettingsFor(
    AiTextGenerationOperation operation,
  ) {
    return promptSettingsByOperation[operation] ??
        const AiTextGenerationPromptSettings();
  }

  AiTextGenerationAgent agentFor(AiTextGenerationOperation operation) {
    return promptSettingsFor(operation).agent ?? agent;
  }

  String? modelForOperation(AiTextGenerationOperation operation) {
    final promptSettings = promptSettingsFor(operation);
    final override = promptSettings.model?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return modelFor(agentFor(operation));
  }

  List<AiTextDiscoveredModel> discoveredModelsFor(AiTextGenerationAgent agent) {
    return discoveredModelsByAgent[agent] ?? const <AiTextDiscoveredModel>[];
  }

  String? discoveredDefaultModelFor(AiTextGenerationAgent agent) {
    final value = discoveredDefaultModelByAgent[agent]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static const AiTextGenerationSettings defaults = AiTextGenerationSettings();

  factory AiTextGenerationSettings.fromJson(Map<String, Object?> json) =>
      AiTextGenerationSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
