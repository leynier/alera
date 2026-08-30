import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_diff_only_execution.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_setting_rows.dart';
import 'package:alera/src/features/settings/presentation/panes/ai_assist_custom_command_dialog.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiAssistSettingsPane extends ConsumerStatefulWidget {
  const AiAssistSettingsPane({
    super.key,
    required this.settings,
    required this.onChanged,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final AiAssistSettings settings;
  final ValueChanged<AiAssistSettings Function(AiAssistSettings)> onChanged;
  final Map<String, GlobalKey> groupKeys;

  @override
  ConsumerState<AiAssistSettingsPane> createState() =>
      _AiAssistSettingsPaneState();
}

class _AiAssistSettingsPaneState extends ConsumerState<AiAssistSettingsPane> {
  static const List<AiAssistOperation> _configuredOperations =
      <AiAssistOperation>[
        AiAssistOperation.commitMessage,
        AiAssistOperation.pullRequestDetails,
        AiAssistOperation.readingDiff,
        AiAssistOperation.workspaceIdentity,
        AiAssistOperation.agentTitle,
        AiAssistOperation.speechMessage,
      ];

  final Map<AiAssistAgent, _AiAssistModelDiscoveryState> _discovery =
      <AiAssistAgent, _AiAssistModelDiscoveryState>{};
  final Set<AiAssistAgent> _autoDiscovered = <AiAssistAgent>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDiscoverConfiguredAgents();
    });
  }

  @override
  void didUpdateWidget(covariant AiAssistSettingsPane oldWidget) {
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
    final spec = aiAssistAgentSpecs[agent];
    final models = modelsForAgent(agent, settings);
    final model = modelForAgent(
      agent,
      settings.modelFor(agent) ?? defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final thinkingLevels = model.thinkingLevels;
    final discovery = _discovery[agent] ?? const _AiAssistModelDiscoveryState();
    final canDiscoverModels = spec?.modelsCommand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: widget.groupKeys['generation'],
          child: AleraSettingsGroup(
            title: 'Generation',
            description:
                'Local agent CLIs run short background jobs from source control and workspace context.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Enable AI Assist',
                description:
                    'Generate text for source control, workspaces, and agent conversations.',
                value: widget.settings.enabled,
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(enabled: value),
                ),
              ),
              SettingsSwitchRow(
                title: 'Auto-Generate Agent Titles',
                description:
                    'Name new agent conversations from their first prompt or recent context.',
                value: settings.autoGenerateAgentTitles,
                onChanged: (value) => widget.onChanged(
                  (settings) =>
                      settings.copyWith(autoGenerateAgentTitles: value),
                ),
              ),
              AiAssistAgentRow(
                value: agent,
                onChanged: (value) => unawaited(_selectAgent(value)),
              ),
              if (agent == AiAssistAgent.custom)
                SettingsTextRow(
                  title: 'Custom Command',
                  description:
                      'Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.',
                  value: settings.customCommand,
                  hintText: 'llm --system commit-message',
                  onChanged: (value) => widget.onChanged(
                    (settings) => settings.copyWith(customCommand: value),
                  ),
                )
              else if (spec != null)
                AiAssistModelRow(
                  agent: agent,
                  models: models,
                  value: model.id,
                  canDiscoverModels: canDiscoverModels,
                  discovering: discovery.loading,
                  discoveryError: discovery.error,
                  onRefreshModels: canDiscoverModels
                      ? () => unawaited(_discoverModels(agent))
                      : null,
                  onChanged: (value) => widget.onChanged((settings) {
                    final selectedModels = <AiAssistAgent, String>{
                      ...settings.selectedModelByAgent,
                    };
                    if (value.trim().isEmpty) {
                      selectedModels.remove(agent);
                    } else {
                      selectedModels[agent] = value;
                    }
                    return settings.copyWith(
                      selectedModelByAgent: selectedModels,
                    );
                  }),
                ),
              if (thinkingLevels.isNotEmpty)
                AiAssistThinkingRow(
                  levels: thinkingLevels,
                  value:
                      settings.thinkingForModel(model.id) ??
                      model.defaultThinkingLevel ??
                      thinkingLevels.first.id,
                  onChanged: (value) => widget.onChanged(
                    (settings) => settings.copyWith(
                      selectedThinkingByModel: <String, String>{
                        ...settings.selectedThinkingByModel,
                        model.id: value,
                      },
                    ),
                  ),
                ),
              if (agent != AiAssistAgent.custom &&
                  _configuredOperations.any(
                    (operation) =>
                        settings.agentFor(operation) == AiAssistAgent.custom,
                  ))
                SettingsTextRow(
                  title: 'Custom Command',
                  description:
                      'Used by prompts that override the global agent with custom command.',
                  value: settings.customCommand,
                  hintText: 'llm --system commit-message',
                  onChanged: (value) => widget.onChanged(
                    (settings) => settings.copyWith(customCommand: value),
                  ),
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
    AiAssistSettings settings,
    AiAssistOperation operation,
  ) {
    final agent = operation == AiAssistOperation.readingDiff
        ? readingDiffAgentForSettings(settings)
        : settings.agentFor(operation);
    if (agent == AiAssistAgent.custom) {
      return const <Widget>[];
    }
    final model = modelForAgent(
      agent,
      (operation == AiAssistOperation.readingDiff
              ? readingDiffModelForSettings(settings, agent)
              : settings.modelForOperation(operation)) ??
          defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    if (model.thinkingLevels.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      AiAssistThinkingRow(
        controlKey: '${operation.key}-reasoning',
        levels: model.thinkingLevels,
        value:
            settings.thinkingForOperation(operation, model.id) ??
            model.defaultThinkingLevel ??
            model.thinkingLevels.first.id,
        onChanged: (value) => widget.onChanged(
          (settings) => settings.copyWith(
            selectedThinkingByOperation:
                <AiAssistOperation, Map<String, String>>{
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
    AiAssistSettings settings,
    AiAssistOperation operation,
  ) {
    return InstructionSettingRow(
      title: 'Instructions',
      value: settings.instructionsFor(operation),
      onChanged: (value) => widget.onChanged(
        (settings) => settings.copyWith(
          instructionsByOperation: <AiAssistOperation, String>{
            ...settings.instructionsByOperation,
            operation: value,
          },
        ),
      ),
    );
  }

  List<Widget> _promptOverrideRows(
    AiAssistSettings settings,
    AiAssistOperation operation,
  ) {
    final promptSettings = settings.promptSettingsFor(operation);
    final isReadingDiff = operation == AiAssistOperation.readingDiff;
    final globalSupported = supportsDiffOnlyAiAssistAgent(settings.agent);
    final agent = isReadingDiff
        ? readingDiffAgentForSettings(settings)
        : settings.agentFor(operation);
    final configuredAgent = promptSettings.agent ?? settings.agent;
    final usesReadingDiffFallback =
        isReadingDiff && !supportsDiffOnlyAiAssistAgent(configuredAgent);
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
    final spec = aiAssistAgentSpecs[agent];
    final discovery = _discovery[agent] ?? const _AiAssistModelDiscoveryState();
    return <Widget>[
      AiAssistPromptAgentRow(
        operation: operation,
        globalAgent: settings.agent,
        value: effectivePromptAgent,
        allowedAgents: isReadingDiff
            ? diffOnlyAiAssistAgents
            : AiAssistAgent.values,
        allowGlobal: !isReadingDiff || globalSupported,
        allowCustom: operation != AiAssistOperation.speechMessage,
        onChanged: (agent) =>
            unawaited(_selectAgent(agent, operation: operation)),
      ),
      if (agent != AiAssistAgent.custom)
        AiAssistPromptModelRow(
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
          onChanged: (model) => widget.onChanged(
            (settings) => _withPromptSettings(
              settings,
              operation,
              AiAssistPromptSettings(agent: effectivePromptAgent, model: model),
            ),
          ),
        ),
    ];
  }

  Future<void> _selectAgent(
    AiAssistAgent? agent, {
    AiAssistOperation? operation,
  }) async {
    String? command;
    if (agent == AiAssistAgent.custom &&
        widget.settings.customCommand.trim().isEmpty) {
      command = await showDialog<String>(
        context: context,
        builder: (_) => const AiAssistCustomCommandDialog(),
      );
      if (!mounted || command == null) return;
    }
    widget.onChanged((settings) {
      if (command != null) settings = settings.copyWith(customCommand: command);
      if (operation == null) {
        return _withGlobalAgent(settings, agent!);
      }
      final previousAgent = settings.agentFor(operation);
      final usesFallback =
          operation == AiAssistOperation.readingDiff &&
          !supportsDiffOnlyAiAssistAgent(previousAgent);
      return _withPromptSettings(
        settings,
        operation,
        AiAssistPromptSettings(
          agent: agent,
          model: !usesFallback && previousAgent == (agent ?? settings.agent)
              ? settings.promptSettingsFor(operation).model
              : null,
        ),
      );
    });
  }

  AiAssistSettings _withPromptSettings(
    AiAssistSettings settings,
    AiAssistOperation operation,
    AiAssistPromptSettings promptSettings,
  ) {
    final updated = <AiAssistOperation, AiAssistPromptSettings>{
      ...settings.promptSettingsByOperation,
    };
    if (promptSettings.inheritsAgent && promptSettings.inheritsModel) {
      updated.remove(operation);
    } else {
      updated[operation] = promptSettings;
    }
    return settings.copyWith(promptSettingsByOperation: updated);
  }

  AiAssistSettings _withGlobalAgent(
    AiAssistSettings settings,
    AiAssistAgent agent,
  ) {
    final updated = <AiAssistOperation, AiAssistPromptSettings>{
      for (final entry in settings.promptSettingsByOperation.entries)
        if (entry.value.agent != null) entry.key: entry.value,
    };
    return settings.copyWith(agent: agent, promptSettingsByOperation: updated);
  }

  void _autoDiscoverConfiguredAgents() {
    if (!mounted || !widget.settings.enabled) {
      return;
    }
    final agents = aiAssistAgentsForModelDiscovery(
      widget.settings,
      _configuredOperations,
    );
    for (final agent in agents) {
      _autoDiscoverAgent(agent);
    }
  }

  void _autoDiscoverAgent(AiAssistAgent agent) {
    final spec = aiAssistAgentSpecs[agent];
    if (spec?.modelsCommand == null ||
        _autoDiscovered.contains(agent) ||
        (_discovery[agent]?.loading ?? false)) {
      return;
    }
    _autoDiscovered.add(agent);
    unawaited(_discoverModels(agent));
  }

  Future<void> _discoverModels(AiAssistAgent agent) async {
    final spec = aiAssistAgentSpecs[agent];
    if (spec?.modelsCommand == null) {
      return;
    }
    setState(() {
      _discovery[agent] = const _AiAssistModelDiscoveryState(loading: true);
    });
    final AiAssistModelDiscoveryResult result;
    try {
      result = await ref
          .read(aiAssistModelDiscoveryServiceProvider)
          .discover(agent);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _discovery[agent] = _AiAssistModelDiscoveryState(
          error: error.toString(),
        );
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _discovery[agent] = _AiAssistModelDiscoveryState(error: result.error);
      });
      return;
    }
    widget.onChanged((latest) {
      final discoveredDefaults = <AiAssistAgent, String>{
        ...latest.discoveredDefaultModelByAgent,
      };
      if (result.defaultModelId == null) {
        discoveredDefaults.remove(agent);
      } else {
        discoveredDefaults[agent] = result.defaultModelId!;
      }
      return latest.copyWith(
        discoveredModelsByAgent: <AiAssistAgent, List<AiAssistDiscoveredModel>>{
          ...latest.discoveredModelsByAgent,
          agent: <AiAssistDiscoveredModel>[
            for (final model in result.models) model.toDiscovered(),
          ],
        },
        discoveredDefaultModelByAgent: discoveredDefaults,
      );
    });
    setState(() {
      _discovery[agent] = const _AiAssistModelDiscoveryState();
    });
  }
}

class _AiAssistModelDiscoveryState {
  const _AiAssistModelDiscoveryState({this.loading = false, this.error});

  final bool loading;
  final String? error;
}
