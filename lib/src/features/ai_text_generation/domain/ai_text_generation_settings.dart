import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'ai_text_generation_settings.mapper.dart';

@MappableEnum()
enum AiTextGenerationOperation {
  commitMessage('commitMessage'),
  pullRequestDetails('pullRequestDetails'),
  branchName('branchName');

  const AiTextGenerationOperation(this.key);

  final String key;

  String get label => switch (this) {
    AiTextGenerationOperation.commitMessage => 'Commit Messages',
    AiTextGenerationOperation.pullRequestDetails => 'Pull Request Details',
    AiTextGenerationOperation.branchName => 'Branch Names',
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
  pi('pi'),
  amp('amp'),
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
    AiTextGenerationAgent.pi => 'Pi',
    AiTextGenerationAgent.amp => 'Amp',
    AiTextGenerationAgent.custom => 'Custom Command',
  };

  AgentType? get agentType => switch (this) {
    AiTextGenerationAgent.codex => AgentType.codex,
    AiTextGenerationAgent.claude => AgentType.claude,
    AiTextGenerationAgent.copilot => AgentType.copilot,
    AiTextGenerationAgent.cursor => AgentType.cursor,
    AiTextGenerationAgent.agy => AgentType.agy,
    AiTextGenerationAgent.opencode => AgentType.opencode,
    AiTextGenerationAgent.pi => AgentType.pi,
    AiTextGenerationAgent.amp => AgentType.amp,
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
class AiTextGenerationSettings with AiTextGenerationSettingsMappable {
  const AiTextGenerationSettings({
    this.enabled = true,
    this.agent = AiTextGenerationAgent.codex,
    this.selectedModelByAgent = const <AiTextGenerationAgent, String>{},
    this.selectedThinkingByModel = const <String, String>{},
    this.discoveredModelsByAgent =
        const <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{},
    this.discoveredDefaultModelByAgent =
        const <AiTextGenerationAgent, String>{},
    this.customCommand = '',
    this.instructionsByOperation = const <AiTextGenerationOperation, String>{},
    this.timeoutSeconds = 120,
  });

  final bool enabled;
  final AiTextGenerationAgent agent;
  final Map<AiTextGenerationAgent, String> selectedModelByAgent;
  final Map<String, String> selectedThinkingByModel;
  final Map<AiTextGenerationAgent, List<AiTextDiscoveredModel>>
  discoveredModelsByAgent;
  final Map<AiTextGenerationAgent, String> discoveredDefaultModelByAgent;
  final String customCommand;
  final Map<AiTextGenerationOperation, String> instructionsByOperation;
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

  String instructionsFor(AiTextGenerationOperation operation) {
    return instructionsByOperation[operation]?.trim() ?? '';
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
