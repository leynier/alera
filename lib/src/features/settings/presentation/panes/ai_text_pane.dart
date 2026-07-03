import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
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
  });

  final AiTextGenerationSettings settings;
  final ValueChanged<AiTextGenerationSettings> onChanged;

  @override
  ConsumerState<AiTextSettingsPane> createState() => _AiTextSettingsPaneState();
}

class _AiTextSettingsPaneState extends ConsumerState<AiTextSettingsPane> {
  final Map<AiTextGenerationAgent, _AiTextModelDiscoveryState> _discovery =
      <AiTextGenerationAgent, _AiTextModelDiscoveryState>{};
  final Set<AiTextGenerationAgent> _autoDiscovered = <AiTextGenerationAgent>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDiscoverActiveAgent();
    });
  }

  @override
  void didUpdateWidget(covariant AiTextSettingsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.agent != widget.settings.agent ||
        oldWidget.settings.enabled != widget.settings.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoDiscoverActiveAgent();
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
        AleraSettingsGroup(
          title: 'Generation',
          description:
              'Local agent CLIs generate text from source control context.',
          children: <Widget>[
            SettingsSwitchRow(
              title: 'Enable AI Text',
              description: 'Show generation actions in source control.',
              value: widget.settings.enabled,
              onChanged: (value) =>
                  widget.onChanged(settings.copyWith(enabled: value)),
            ),
            AiTextAgentRow(
              value: agent,
              onChanged: (value) =>
                  widget.onChanged(settings.copyWith(agent: value)),
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
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    selectedModelByAgent: <AiTextGenerationAgent, String>{
                      ...settings.selectedModelByAgent,
                      agent: value,
                    },
                  ),
                ),
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
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Instructions',
          description: 'Extra guidance appended to commit-message prompts.',
          children: <Widget>[
            InstructionSettingRow(
              title: AiTextGenerationOperation.commitMessage.label,
              value: settings.instructionsFor(
                AiTextGenerationOperation.commitMessage,
              ),
              onChanged: (value) => widget.onChanged(
                settings.copyWith(
                  instructionsByOperation: <AiTextGenerationOperation, String>{
                    ...settings.instructionsByOperation,
                    AiTextGenerationOperation.commitMessage: value,
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _autoDiscoverActiveAgent() {
    if (!mounted || !widget.settings.enabled) {
      return;
    }
    final agent = widget.settings.agent;
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
    widget.onChanged(
      latest.copyWith(
        discoveredModelsByAgent:
            <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{
              ...latest.discoveredModelsByAgent,
              agent: <AiTextDiscoveredModel>[
                for (final model in result.models) model.toDiscovered(),
              ],
            },
        discoveredDefaultModelByAgent: <AiTextGenerationAgent, String>{
          ...latest.discoveredDefaultModelByAgent,
          agent: result.defaultModelId,
        },
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
