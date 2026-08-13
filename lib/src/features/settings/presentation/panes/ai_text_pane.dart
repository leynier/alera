import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_diff_only_execution.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_model_discovery_service.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_text_setting_rows.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiTextSettingsPane extends ConsumerStatefulWidget {
  const AiTextSettingsPane({
    super.key,
    required this.settings,
    required this.onChanged,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final AiTextGenerationSettings settings;
  final ValueChanged<AiTextGenerationSettings> onChanged;
  final Map<String, GlobalKey> groupKeys;

  @override
  ConsumerState<AiTextSettingsPane> createState() => _AiTextSettingsPaneState();
}

class _AiTextSettingsPaneState extends ConsumerState<AiTextSettingsPane> {
  static const List<AiTextGenerationOperation> _configuredOperations =
      <AiTextGenerationOperation>[
        AiTextGenerationOperation.commitMessage,
        AiTextGenerationOperation.pullRequestDetails,
        AiTextGenerationOperation.readingDiff,
        AiTextGenerationOperation.workspaceIdentity,
      ];

  final Map<AiTextGenerationAgent, _AiTextModelDiscoveryState> _discovery =
      <AiTextGenerationAgent, _AiTextModelDiscoveryState>{};
  final Set<AiTextGenerationAgent> _autoDiscovered = <AiTextGenerationAgent>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDiscoverConfiguredAgents();
    });
  }

  @override
  void didUpdateWidget(covariant AiTextSettingsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.agent != widget.settings.agent ||
        oldWidget.settings.enabled != widget.settings.enabled ||
        oldWidget.settings.promptSettingsByOperation !=
            widget.settings.promptSettingsByOperation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoDiscoverConfiguredAgents();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final agent = settings.agent;
    final spec = aiTextAgentSpecs[agent];
    final models = modelsForAgent(agent, settings);
    final model = modelForAgent(
      agent,
      settings.modelFor(agent) ?? defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final thinkingLevels = model.thinkingLevels;
    final discovery = _discovery[agent] ?? const _AiTextModelDiscoveryState();
    final canDiscoverModels = spec?.modelsCommand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: widget.groupKeys['generation'],
          child: AleraSettingsGroup(
            title: 'Generation',
            description:
                'Local agent CLIs generate text from source control context.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Enable AI Text',
                description:
                    'Show generation actions in source control and pull requests.',
                value: widget.settings.enabled,
                onChanged: (value) =>
                    widget.onChanged(settings.copyWith(enabled: value)),
              ),
              AiTextAgentRow(
                value: agent,
                onChanged: (value) =>
                    widget.onChanged(_withGlobalAgent(settings, value)),
              ),
              if (agent == AiTextGenerationAgent.custom)
                SettingsTextRow(
                  title: 'Custom Command',
                  description:
                      'Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.',
                  value: settings.customCommand,
                  hintText: 'llm --system commit-message',
                  onChanged: (value) =>
                      widget.onChanged(settings.copyWith(customCommand: value)),
                )
              else if (spec != null)
                AiTextModelRow(
                  agent: agent,
                  models: models,
                  value: model.id,
                  canDiscoverModels: canDiscoverModels,
                  discovering: discovery.loading,
                  discoveryError: discovery.error,
                  onRefreshModels: canDiscoverModels
                      ? () => unawaited(_discoverModels(agent))
                      : null,
                  onChanged: (value) {
                    final selectedModels = <AiTextGenerationAgent, String>{
                      ...settings.selectedModelByAgent,
                    };
                    if (value.trim().isEmpty) {
                      selectedModels.remove(agent);
                    } else {
                      selectedModels[agent] = value;
                    }
                    widget.onChanged(
                      settings.copyWith(selectedModelByAgent: selectedModels),
                    );
                  },
                ),
              if (thinkingLevels.isNotEmpty)
                AiTextThinkingRow(
                  levels: thinkingLevels,
                  value:
                      settings.thinkingForModel(model.id) ??
                      model.defaultThinkingLevel ??
                      thinkingLevels.first.id,
                  onChanged: (value) => widget.onChanged(
                    settings.copyWith(
                      selectedThinkingByModel: <String, String>{
                        ...settings.selectedThinkingByModel,
                        model.id: value,
                      },
                    ),
                  ),
                ),
              if (agent != AiTextGenerationAgent.custom &&
                  _configuredOperations.any(
                    (operation) =>
                        settings.agentFor(operation) ==
                        AiTextGenerationAgent.custom,
                  ))
                SettingsTextRow(
                  title: 'Custom Command',
                  description:
                      'Used by prompts that override the global agent with custom command.',
                  value: settings.customCommand,
                  hintText: 'llm --system commit-message',
                  onChanged: (value) =>
                      widget.onChanged(settings.copyWith(customCommand: value)),
                ),
            ],
          ),
        ),
        for (final operation in _configuredOperations) ...<Widget>[
          KeyedSubtree(
            key: widget.groupKeys[operation.key],
            child: AleraSettingsGroup(
              title: operation.label,
              description:
                  'Configure the agent, model, reasoning and instructions for this prompt.',
              children: <Widget>[
                ..._promptOverrideRows(settings, operation),
                ..._thinkingRows(settings, operation),
                _instructionRow(settings, operation),
              ],
            ),
          ),
          if (operation != _configuredOperations.last)
            const SizedBox(height: AleraTokens.space16),
        ],
      ],
    );
  }

  List<Widget> _thinkingRows(
    AiTextGenerationSettings settings,
    AiTextGenerationOperation operation,
  ) {
    final agent = operation == AiTextGenerationOperation.readingDiff
        ? readingDiffAgentForSettings(settings)
        : settings.agentFor(operation);
    if (agent == AiTextGenerationAgent.custom) {
      return const <Widget>[];
    }
    final model = modelForAgent(
      agent,
      settings.modelForOperation(operation) ??
          defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    if (model.thinkingLevels.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      AiTextThinkingRow(
        controlKey: '${operation.key}-reasoning',
        levels: model.thinkingLevels,
        value:
            settings.thinkingForOperation(operation, model.id) ??
            model.defaultThinkingLevel ??
            model.thinkingLevels.first.id,
        onChanged: (value) => widget.onChanged(
          settings.copyWith(
            selectedThinkingByOperation:
                <AiTextGenerationOperation, Map<String, String>>{
                  ...settings.selectedThinkingByOperation,
                  operation: <String, String>{
                    ...settings.selectedThinkingByOperation[operation] ??
                        const <String, String>{},
                    model.id: value,
                  },
                },
          ),
        ),
      ),
    ];
  }

  Widget _instructionRow(
    AiTextGenerationSettings settings,
    AiTextGenerationOperation operation,
  ) {
    return InstructionSettingRow(
      title: 'Instructions',
      value: settings.instructionsFor(operation),
      onChanged: (value) => widget.onChanged(
        settings.copyWith(
          instructionsByOperation: <AiTextGenerationOperation, String>{
            ...settings.instructionsByOperation,
            operation: value,
          },
        ),
      ),
    );
  }

  List<Widget> _promptOverrideRows(
    AiTextGenerationSettings settings,
    AiTextGenerationOperation operation,
  ) {
    final promptSettings = settings.promptSettingsFor(operation);
    final isReadingDiff = operation == AiTextGenerationOperation.readingDiff;
    final globalSupported = supportsDiffOnlyAiTextAgent(settings.agent);
    final agent = isReadingDiff
        ? readingDiffAgentForSettings(settings)
        : settings.agentFor(operation);
    final configuredAgent = promptSettings.agent ?? settings.agent;
    final usesReadingDiffFallback =
        isReadingDiff && !supportsDiffOnlyAiTextAgent(configuredAgent);
    final effectivePromptAgent = usesReadingDiffFallback
        ? agent
        : promptSettings.agent;
    final effectivePromptModel = usesReadingDiffFallback
        ? null
        : promptSettings.model;
    final inheritedModel = modelForAgent(
      agent,
      settings.modelFor(agent) ?? defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final spec = aiTextAgentSpecs[agent];
    final discovery = _discovery[agent] ?? const _AiTextModelDiscoveryState();
    return <Widget>[
      AiTextPromptAgentRow(
        operation: operation,
        globalAgent: settings.agent,
        value: effectivePromptAgent,
        allowedAgents: isReadingDiff
            ? diffOnlyAiTextAgents
            : AiTextGenerationAgent.values,
        allowGlobal: !isReadingDiff || globalSupported,
        onChanged: (agent) {
          final previousAgent = isReadingDiff
              ? readingDiffAgentForSettings(settings)
              : settings.agentFor(operation);
          final nextAgent = agent ?? settings.agent;
          _updatePromptSettings(
            settings,
            operation,
            AiTextGenerationPromptSettings(
              agent: agent,
              model: previousAgent == nextAgent ? promptSettings.model : null,
            ),
          );
        },
      ),
      if (agent != AiTextGenerationAgent.custom)
        AiTextPromptModelRow(
          operation: operation,
          agent: agent,
          models: modelsForAgent(agent, settings),
          inheritedModel: inheritedModel,
          value: effectivePromptModel,
          discovering: discovery.loading,
          discoveryError: discovery.error,
          onRefreshModels: spec?.modelsCommand == null
              ? null
              : () => unawaited(_discoverModels(agent)),
          onChanged: (model) {
            _updatePromptSettings(
              settings,
              operation,
              AiTextGenerationPromptSettings(
                agent: effectivePromptAgent,
                model: model,
              ),
            );
          },
        ),
    ];
  }

  void _updatePromptSettings(
    AiTextGenerationSettings settings,
    AiTextGenerationOperation operation,
    AiTextGenerationPromptSettings promptSettings,
  ) {
    final updated = <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
      ...settings.promptSettingsByOperation,
    };
    if (promptSettings.inheritsAgent && promptSettings.inheritsModel) {
      updated.remove(operation);
    } else {
      updated[operation] = promptSettings;
    }
    widget.onChanged(settings.copyWith(promptSettingsByOperation: updated));
  }

  AiTextGenerationSettings _withGlobalAgent(
    AiTextGenerationSettings settings,
    AiTextGenerationAgent agent,
  ) {
    final updated = <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
      for (final entry in settings.promptSettingsByOperation.entries)
        if (entry.value.agent != null) entry.key: entry.value,
    };
    return settings.copyWith(agent: agent, promptSettingsByOperation: updated);
  }

  void _autoDiscoverConfiguredAgents() {
    if (!mounted || !widget.settings.enabled) {
      return;
    }
    final agents = <AiTextGenerationAgent>{
      widget.settings.agent,
      for (final operation in _configuredOperations)
        widget.settings.agentFor(operation),
    };
    for (final agent in agents) {
      _autoDiscoverAgent(agent);
    }
  }

  void _autoDiscoverAgent(AiTextGenerationAgent agent) {
    final spec = aiTextAgentSpecs[agent];
    if (spec?.modelsCommand == null ||
        _autoDiscovered.contains(agent) ||
        (_discovery[agent]?.loading ?? false)) {
      return;
    }
    _autoDiscovered.add(agent);
    unawaited(_discoverModels(agent));
  }

  Future<void> _discoverModels(AiTextGenerationAgent agent) async {
    final spec = aiTextAgentSpecs[agent];
    if (spec?.modelsCommand == null) {
      return;
    }
    setState(() {
      _discovery[agent] = const _AiTextModelDiscoveryState(loading: true);
    });
    final AiTextModelDiscoveryResult result;
    try {
      result = await ref
          .read(aiTextModelDiscoveryServiceProvider)
          .discover(agent);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _discovery[agent] = _AiTextModelDiscoveryState(error: error.toString());
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _discovery[agent] = _AiTextModelDiscoveryState(error: result.error);
      });
      return;
    }
    final latest = widget.settings;
    final discoveredDefaults = <AiTextGenerationAgent, String>{
      ...latest.discoveredDefaultModelByAgent,
    };
    if (result.defaultModelId == null) {
      discoveredDefaults.remove(agent);
    } else {
      discoveredDefaults[agent] = result.defaultModelId!;
    }
    widget.onChanged(
      latest.copyWith(
        discoveredModelsByAgent:
            <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{
              ...latest.discoveredModelsByAgent,
              agent: <AiTextDiscoveredModel>[
                for (final model in result.models) model.toDiscovered(),
              ],
            },
        discoveredDefaultModelByAgent: discoveredDefaults,
      ),
    );
    setState(() {
      _discovery[agent] = const _AiTextModelDiscoveryState();
    });
  }
}

class _AiTextModelDiscoveryState {
  const _AiTextModelDiscoveryState({this.loading = false, this.error});

  final bool loading;
  final String? error;
}
