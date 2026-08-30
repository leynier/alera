import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'ai_assist_settings.mapper.dart';

@MappableEnum()
enum AiAssistOperation {
  commitMessage('commitMessage'),
  pullRequestDetails('pullRequestDetails'),
  branchName('branchName'),
  readingDiff('readingDiff'),
  workspaceIdentity('workspaceIdentity'),
  agentTitle('agentTitle'),
  speechMessage('speechMessage');

  const AiAssistOperation(this.key);

  final String key;

  String get label => switch (this) {
    AiAssistOperation.commitMessage => 'Commit Messages',
    AiAssistOperation.pullRequestDetails => 'Pull Request Details',
    AiAssistOperation.branchName => 'Branch Names',
    AiAssistOperation.readingDiff => 'Reading Diffs',
    AiAssistOperation.workspaceIdentity => 'Workspace Identity',
    AiAssistOperation.agentTitle => 'Agent Titles',
    AiAssistOperation.speechMessage => 'Speech Messages',
  };
}

@MappableEnum()
enum AiAssistAgent {
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

  const AiAssistAgent(this.key);

  final String key;

  String get label => switch (this) {
    AiAssistAgent.codex => 'Codex',
    AiAssistAgent.claude => 'Claude Code',
    AiAssistAgent.copilot => 'GitHub Copilot',
    AiAssistAgent.cursor => 'Cursor',
    AiAssistAgent.agy => 'Antigravity',
    AiAssistAgent.opencode => 'OpenCode',
    AiAssistAgent.opencode2 => 'OpenCode 2',
    AiAssistAgent.pi => 'Pi',
    AiAssistAgent.amp => 'Amp',
    AiAssistAgent.grok => 'Grok Build',
    AiAssistAgent.fx => 'fx',
    AiAssistAgent.custom => 'Custom Command',
  };

  AgentType? get agentType => switch (this) {
    AiAssistAgent.codex => AgentType.codex,
    AiAssistAgent.claude => AgentType.claude,
    AiAssistAgent.copilot => AgentType.copilot,
    AiAssistAgent.cursor => AgentType.cursor,
    AiAssistAgent.agy => AgentType.agy,
    AiAssistAgent.opencode => AgentType.opencode,
    AiAssistAgent.opencode2 => AgentType.opencode2,
    AiAssistAgent.pi => AgentType.pi,
    AiAssistAgent.amp => AgentType.amp,
    AiAssistAgent.grok => AgentType.grok,
    AiAssistAgent.fx => AgentType.fx,
    AiAssistAgent.custom => null,
  };
}

@MappableClass()
class AiAssistDiscoveredThinkingLevel
    with AiAssistDiscoveredThinkingLevelMappable {
  const AiAssistDiscoveredThinkingLevel({
    required this.id,
    required this.label,
  });

  final String id;
  final String label;
}

@MappableClass()
class AiAssistDiscoveredModel with AiAssistDiscoveredModelMappable {
  const AiAssistDiscoveredModel({
    required this.id,
    required this.label,
    this.thinkingLevels = const <AiAssistDiscoveredThinkingLevel>[],
    this.defaultThinkingLevel,
  });

  final String id;
  final String label;
  final List<AiAssistDiscoveredThinkingLevel> thinkingLevels;
  final String? defaultThinkingLevel;
}

@MappableClass()
class AiAssistPromptSettings with AiAssistPromptSettingsMappable {
  const AiAssistPromptSettings({this.agent, this.model});

  final AiAssistAgent? agent;
  final String? model;

  bool get inheritsAgent => agent == null;

  bool get inheritsModel => model == null || model!.trim().isEmpty;
}

@MappableClass()
class AiAssistSettings with AiAssistSettingsMappable {
  const AiAssistSettings({
    this.enabled = true,
    this.autoGenerateAgentTitles = true,
    this.agent = AiAssistAgent.codex,
    this.selectedModelByAgent = const <AiAssistAgent, String>{},
    this.selectedThinkingByModel = const <String, String>{},
    this.selectedThinkingByOperation =
        const <AiAssistOperation, Map<String, String>>{},
    this.discoveredModelsByAgent =
        const <AiAssistAgent, List<AiAssistDiscoveredModel>>{},
    this.discoveredDefaultModelByAgent = const <AiAssistAgent, String>{},
    this.customCommand = '',
    this.instructionsByOperation = const <AiAssistOperation, String>{},
    this.promptSettingsByOperation =
        const <AiAssistOperation, AiAssistPromptSettings>{},
    this.timeoutSeconds = 120,
  });

  final bool enabled;
  final bool autoGenerateAgentTitles;
  final AiAssistAgent agent;
  final Map<AiAssistAgent, String> selectedModelByAgent;
  final Map<String, String> selectedThinkingByModel;
  final Map<AiAssistOperation, Map<String, String>> selectedThinkingByOperation;
  final Map<AiAssistAgent, List<AiAssistDiscoveredModel>>
  discoveredModelsByAgent;
  final Map<AiAssistAgent, String> discoveredDefaultModelByAgent;
  final String customCommand;
  final Map<AiAssistOperation, String> instructionsByOperation;
  final Map<AiAssistOperation, AiAssistPromptSettings>
  promptSettingsByOperation;
  final int timeoutSeconds;

  String? modelFor(AiAssistAgent agent) {
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

  String? thinkingForOperation(AiAssistOperation operation, String? model) {
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

  String instructionsFor(AiAssistOperation operation) {
    return instructionsByOperation[operation]?.trim() ?? '';
  }

  AiAssistPromptSettings promptSettingsFor(AiAssistOperation operation) {
    return promptSettingsByOperation[operation] ??
        const AiAssistPromptSettings();
  }

  AiAssistAgent agentFor(AiAssistOperation operation) {
    return promptSettingsFor(operation).agent ?? agent;
  }

  String? modelForOperation(AiAssistOperation operation) {
    final promptSettings = promptSettingsFor(operation);
    final override = promptSettings.model?.trim();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return modelFor(agentFor(operation));
  }

  List<AiAssistDiscoveredModel> discoveredModelsFor(AiAssistAgent agent) {
    return discoveredModelsByAgent[agent] ?? const <AiAssistDiscoveredModel>[];
  }

  String? discoveredDefaultModelFor(AiAssistAgent agent) {
    final value = discoveredDefaultModelByAgent[agent]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static const AiAssistSettings defaults = AiAssistSettings();

  factory AiAssistSettings.fromJson(Map<String, Object?> json) =>
      AiAssistSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
