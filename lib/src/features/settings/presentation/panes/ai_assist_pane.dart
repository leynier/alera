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
import 'package:alera/src/features/settings/presentation/panes/chatgpt_account_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'ai_assist_pane_discovery.dart';
part 'ai_assist_pane_options.dart';

class const AiAssistSettingsPane({
  super.key,
  required final AiAssistSettings settings,
  required final ValueChanged<AiAssistSettings Function(AiAssistSettings)>
  onChanged,
  final Map<String, GlobalKey> groupKeys = const <String, GlobalKey>{},
}) extends ConsumerStatefulWidget {
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

  final Map<AiAssistAgent, AiAssistModelDiscoveryState> _discovery =
      <AiAssistAgent, AiAssistModelDiscoveryState>{};
  final Map<AiAssistAgent, int> _discoveryGeneration = {};
  final Set<AiAssistAgent> _autoDiscovered = <AiAssistAgent>{};
  bool _chatGptOptionsSupported = true;
  bool _chatGptOptionsChecked = false;

  void _updateChatGptOptionsSupported(bool supported) {
    if (!mounted) return;
    setState(() => _chatGptOptionsSupported = supported);
  }

  void _updateDiscoveryState(
    AiAssistAgent agent,
    AiAssistModelDiscoveryState state,
  ) {
    if (!mounted) return;
    setState(() => _discovery[agent] = state);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDiscoverConfiguredAgents();
      _loadChatGptOptionsSupport();
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
        _loadChatGptOptionsSupport();
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
    final discovery = _discovery[agent] ?? const AiAssistModelDiscoveryState();
    final canDiscoverModels = spec?.canDiscoverModels ?? false;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        KeyedSubtree(
          key: widget.groupKeys['generation'],
          child: AleraSettingsGroup(
            title: 'Generation',
            description: 'Connected providers run short background jobs from source control and workspace context.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Enable AI Assist',
                description: 'Generate text for source control, workspaces, and agent conversations.',
                value: widget.settings.enabled,
                onChanged: (value) => widget.onChanged(
                  (settings) => settings.copyWith(enabled: value),
                ),
              ),
              SettingsSwitchRow(
                title: 'Auto-Generate Agent Titles',
                description: 'Name new agent conversations from their first prompt or recent context.',
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
                  description: 'Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.',
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
              if (thinkingLevels.isNotEmpty ||
                  agent == AiAssistAgent.chatgpt &&
                      settings.thinkingForModel(model.id) != null)
                AiAssistThinkingRow(
                  levels: thinkingLevels,
                  value: agent == AiAssistAgent.chatgpt
                      ? settings.thinkingForModel(model.id)
                      : settings.thinkingForModel(model.id) ??
                            model.defaultThinkingLevel ??
                            thinkingLevels.first.id,
                  allowProviderDefault: agent == AiAssistAgent.chatgpt,
                  onChanged: (value) => widget.onChanged(
                    (settings) =>
                        _updateGlobalThinking(settings, model.id, value),
                  ),
                ),
              if (_usesChatGpt(settings))
                ChatGptModelSpeedRow(
                  value: settings.effectiveChatGptServiceTier,
                  enabled: _chatGptOptionsSupported,
                  availabilityMessage: _chatGptOptionsSupported
                      ? null
                      : 'Update Alera to use ChatGPT speed controls.',
                  onChanged: (value) => widget.onChanged(
                    (settings) => settings.copyWith(chatGptServiceTier: value),
                  ),
                ),
              if (agent != AiAssistAgent.custom &&
                  _configuredOperations.any(
                    (operation) =>
                        settings.agentFor(operation) == AiAssistAgent.custom,
                  ))
                SettingsTextRow(
                  title: 'Custom Command',
                  description: 'Used by prompts that override the global agent with custom command.',
                  value: settings.customCommand,
                  hintText: 'llm --system commit-message',
                  onChanged: (value) => widget.onChanged(
                    (settings) => settings.copyWith(customCommand: value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['chatgpt'],
          child: ChatGptAccountSettings(
            onAccountChanged: _chatGptAccountChanged,
            onAccountReady: _chatGptAccountReady,
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        for (final operation in _configuredOperations) ...<Widget>[
          KeyedSubtree(
            key: widget.groupKeys[operation.key],
            child: AleraSettingsGroup(
              title: operation.label,
              description: 'Configure the agent, model, reasoning and instructions for this prompt.',
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

  void _chatGptAccountChanged() {
    widget.onChanged(
      (settings) => settings.copyWith(
        selectedModelByAgent: {...settings.selectedModelByAgent}
          ..remove(AiAssistAgent.chatgpt),
        discoveredModelsByAgent: {...settings.discoveredModelsByAgent}
          ..remove(AiAssistAgent.chatgpt),
        discoveredDefaultModelByAgent: {
          ...settings.discoveredDefaultModelByAgent,
        }..remove(AiAssistAgent.chatgpt),
        promptSettingsByOperation: {
          for (final entry in settings.promptSettingsByOperation.entries)
            entry.key: settings.agentFor(entry.key) == AiAssistAgent.chatgpt
                ? AiAssistPromptSettings(agent: entry.value.agent)
                : entry.value,
        },
      ),
    );
    _loadChatGptOptionsSupport();
    unawaited(_discoverModels(AiAssistAgent.chatgpt, force: true));
  }

  void _chatGptAccountReady() {
    _loadChatGptOptionsSupport();
    unawaited(_discoverModels(AiAssistAgent.chatgpt));
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
    if (model.thinkingLevels.isEmpty &&
        !(agent == AiAssistAgent.chatgpt &&
            settings.thinkingForOperation(operation, model.id) != null)) {
      return const <Widget>[];
    }
    final operationThinking =
        settings.selectedThinkingByOperation[operation]?[model.id];
    final isChatGpt = agent == AiAssistAgent.chatgpt;
    final inheritedThinking = settings.thinkingForModel(model.id);
    var inheritedLabel = 'Inherit Global';
    String? inheritedUnavailableValue;
    if (inheritedThinking != null) {
      inheritedUnavailableValue = inheritedThinking;
      for (final level in model.thinkingLevels) {
        if (level.id == inheritedThinking) {
          inheritedUnavailableValue = null;
          inheritedLabel = 'Inherit Global (${level.label})';
          break;
        }
      }
    }
    return <Widget>[
      AiAssistThinkingRow(
        controlKey: '${operation.key}-reasoning',
        levels: model.thinkingLevels,
        value: isChatGpt
            ? operationThinking
            : settings.thinkingForOperation(operation, model.id) ??
                  model.defaultThinkingLevel ??
                  model.thinkingLevels.first.id,
        allowInherited: isChatGpt,
        inheritedLabel: inheritedLabel,
        inheritedUnavailableValue: isChatGpt ? inheritedUnavailableValue : null,
        onChanged: (value) => widget.onChanged(
          (settings) =>
              _updateOperationThinking(settings, operation, model.id, value),
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
    final discovery = _discovery[agent] ?? const AiAssistModelDiscoveryState();
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
          onRefreshModels: spec == null || !spec.canDiscoverModels
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
}
