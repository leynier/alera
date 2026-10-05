import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/chatgpt_account_rows.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

class const AiAssistAgentRow({
  super.key,
  required final AiAssistAgent value,
  required final ValueChanged<AiAssistAgent> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Agent',
      description: 'Provider used for AI Assist jobs.',
      child: AleraDropdownField<AiAssistAgent>(
        key: ValueKey<String>('ai-assist-agent-${value.key}'),
        value: value,
        entries: <AleraDropdownFieldEntry<AiAssistAgent>>[
          for (final agent in AiAssistAgent.values)
            AleraDropdownFieldEntry<AiAssistAgent>(
              value: agent,
              label: agent.label,
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class const AiAssistModelRow({
  super.key,
  required final AiAssistAgent agent,
  required final List<AiAssistModel> models,
  required final String value,
  required final bool canDiscoverModels,
  required final bool discovering,
  required final String? discoveryError,
  required final VoidCallback? onRefreshModels,
  required final ValueChanged<String> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final selected = value.trim();
    final known = models.any((model) => model.id == selected);
    final keepUnknownSelection =
        agent == AiAssistAgent.chatgpt && canDiscoverModels;
    if (!known && !keepUnknownSelection) {
      return SettingsTextRow(
        title: 'Model',
        description: 'Model passed to ${agent.label}.',
        value: value,
        onChanged: onChanged,
      );
    }
    final entries = <AiAssistModel>[
      if (!known && selected.isNotEmpty) modelForAgent(agent, selected),
      ...models,
    ];
    return AleraSettingRow(
      title: 'Model',
      description: discoveryError == null
          ? agent == AiAssistAgent.chatgpt
                ? '$chatGptPlanInUseLabel. Models follow the active account.'
                : 'Model passed to ${agent.label}.'
          : discoveryError!,
      child: Row(
        children: <Widget>[
          Expanded(
            child: AleraDropdownField<String>(
              key: ValueKey<String>('ai-assist-model-${agent.key}-$selected'),
              value: selected,
              entries: <AleraDropdownFieldEntry<String>>[
                for (final model in entries)
                  AleraDropdownFieldEntry<String>(
                    value: model.id,
                    label: model.id == selected && !known
                        ? 'Unavailable (${model.label})'
                        : model.label,
                    enabled: model.id != selected || known,
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
          if (canDiscoverModels) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Refresh Models',
              icon: discovering ? AleraIcons.sync : AleraIcons.refresh,
              onPressed: discovering ? null : onRefreshModels,
            ),
          ],
        ],
      ),
    );
  }
}

class const AiAssistThinkingRow({
  super.key,
  final String controlKey = 'thinking',
  required final List<AiThinkingLevel> levels,
  required final String? value,
  required final ValueChanged<String?> onChanged,
  final bool allowProviderDefault = false,
  final bool allowInherited = false,
  final String inheritedLabel = 'Inherit Global',
  final String? inheritedUnavailableValue,
}) extends StatelessWidget {
  static const String _inheritedSelection = '\u0000inherit-global';
  static const String _unavailableInheritedSelection =
      '\u0000unavailable-inherited';

  @override
  Widget build(BuildContext context) {
    final hasSelectedLevel =
        value != null && levels.any((level) => level.id == value);
    final unsupportedValue =
        (allowProviderDefault || allowInherited) &&
            value != null &&
            !hasSelectedLevel
        ? value
        : null;
    final unsupportedInheritedValue =
        allowInherited && value == null && inheritedUnavailableValue != null
        ? inheritedUnavailableValue
        : null;
    final selected = hasSelectedLevel
        ? value
        : unsupportedValue ??
              (unsupportedInheritedValue != null
                  ? _unavailableInheritedSelection
                  : allowInherited
                  ? _inheritedSelection
                  : allowProviderDefault
                  ? null
                  : levels.first.id);
    final recoveryLabel = allowProviderDefault
        ? 'Provider Default'
        : allowInherited
        ? 'Inherit Global'
        : 'a supported level';
    final description = unsupportedValue != null
        ? 'The saved reasoning level is unavailable for this model. Choose $recoveryLabel or a supported level.'
        : unsupportedInheritedValue != null
        ? 'The global reasoning level "$unsupportedInheritedValue" is unavailable for this model. Choose Provider Default in the global AI Assist settings or a supported level here.'
        : allowInherited
        ? 'Reasoning effort inherited from global AI Assist settings.'
        : 'Reasoning effort for models that support it.';
    return AleraSettingRow(
      title: 'Reasoning',
      description: description,
      child: AleraDropdownField<String?>(
        key: ValueKey<String>(
          'ai-assist-$controlKey-${value ?? (allowInherited ? 'inherit' : 'default')}',
        ),
        value: selected,
        entries: <AleraDropdownFieldEntry<String?>>[
          if (allowInherited)
            AleraDropdownFieldEntry<String?>(
              value: _inheritedSelection,
              label: inheritedLabel,
            ),
          if (unsupportedInheritedValue != null)
            AleraDropdownFieldEntry<String?>(
              value: _unavailableInheritedSelection,
              label: 'Unavailable (Global: $unsupportedInheritedValue)',
              enabled: false,
            ),
          if (allowProviderDefault)
            const AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'Provider Default',
            ),
          if (unsupportedValue != null)
            AleraDropdownFieldEntry<String?>(
              value: unsupportedValue,
              label: 'Unavailable ($unsupportedValue)',
              enabled: false,
            ),
          for (final level in levels)
            AleraDropdownFieldEntry<String?>(
              value: level.id,
              label: level.label,
            ),
        ],
        onChanged: (value) =>
            onChanged(value == _inheritedSelection ? null : value),
      ),
    );
  }
}

class const ChatGptModelSpeedRow({
  super.key,
  required final String value,
  required final ValueChanged<String> onChanged,
  final bool enabled = true,
  final String? availabilityMessage,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final selected = value == aiAssistChatGptFastServiceTier
        ? aiAssistChatGptFastServiceTier
        : aiAssistChatGptDefaultServiceTier;
    return AleraSettingRow(
      title: 'ChatGPT Speed',
      description: availabilityMessage ?? 'Applies to ChatGPT jobs. Request faster processing when available. Uses your ChatGPT plan faster.',
      child: AleraDropdownField<String>(
        key: ValueKey<String>('ai-assist-chatgpt-speed-$selected'),
        value: selected,
        entries: <AleraDropdownFieldEntry<String>>[
          AleraDropdownFieldEntry<String>(
            value: aiAssistChatGptDefaultServiceTier,
            label: 'Normal',
          ),
          AleraDropdownFieldEntry<String>(
            value: aiAssistChatGptFastServiceTier,
            label: 'Fast',
            enabled: enabled,
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class const AiAssistPromptAgentRow({
  super.key,
  required final AiAssistOperation operation,
  required final AiAssistAgent globalAgent,
  required final AiAssistAgent? value,
  final List<AiAssistAgent> allowedAgents = AiAssistAgent.values,
  final bool allowGlobal = true,
  required final ValueChanged<AiAssistAgent?> onChanged,
  final bool allowCustom = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Agent',
      description: 'Override the global agent for this prompt.',
      child: AleraDropdownField<AiAssistAgent?>(
        key: ValueKey<String>(
          'ai-assist-${operation.key}-agent-${value?.key ?? 'global'}',
        ),
        value: value,
        entries: <AleraDropdownFieldEntry<AiAssistAgent?>>[
          if (allowGlobal)
            AleraDropdownFieldEntry<AiAssistAgent?>(
              value: null,
              label: 'Global (${globalAgent.label})',
            ),
          for (final agent in allowedAgents)
            if (allowCustom || agent != AiAssistAgent.custom)
              AleraDropdownFieldEntry<AiAssistAgent?>(
                value: agent,
                label: agent.label,
              ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class const AiAssistPromptModelRow({
  super.key,
  required final AiAssistOperation operation,
  required final AiAssistAgent agent,
  required final List<AiAssistModel> models,
  required final AiAssistModel inheritedModel,
  required final String? value,
  required final bool discovering,
  required final String? discoveryError,
  required final VoidCallback? onRefreshModels,
  required final ValueChanged<String?> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final selected = value?.trim();
    final known =
        selected == null || models.any((model) => model.id == selected);
    final entries = <AiAssistModel>[
      ...models,
      if (selected != null && selected.isNotEmpty && !known)
        modelForAgent(agent, selected),
    ];
    return AleraSettingRow(
      title: 'Model',
      description:
          discoveryError ?? 'Override the global model for this prompt.',
      child: Row(
        children: <Widget>[
          Expanded(
            child: AleraDropdownField<String?>(
              key: ValueKey<String>(
                'ai-assist-${operation.key}-model-${selected ?? 'global'}',
              ),
              value: selected == null || selected.isEmpty ? null : selected,
              entries: <AleraDropdownFieldEntry<String?>>[
                AleraDropdownFieldEntry<String?>(
                  value: null,
                  label: 'Global (${inheritedModel.label})',
                ),
                for (final model in entries)
                  AleraDropdownFieldEntry<String?>(
                    value: model.id,
                    label:
                        agent == AiAssistAgent.chatgpt &&
                            model.id == selected &&
                            !known
                        ? 'Unavailable (${model.label})'
                        : model.label,
                    enabled:
                        agent != AiAssistAgent.chatgpt ||
                        model.id != selected ||
                        known,
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
          if (onRefreshModels != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Refresh Models',
              icon: discovering ? AleraIcons.sync : AleraIcons.refresh,
              onPressed: discovering ? null : onRefreshModels,
            ),
          ],
        ],
      ),
    );
  }
}

class const InstructionSettingRow({
  super.key,
  required final String title,
  required final String value,
  required final ValueChanged<String> onChanged,
}) extends StatefulWidget {
  @override
  State<InstructionSettingRow> createState() => _InstructionSettingRowState();
}

class _InstructionSettingRowState extends State<InstructionSettingRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(InstructionSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: 'Optional prompt guidance.',
      controlWidth: 360,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
        minLines: 2,
        maxLines: 4,
        onEditingComplete: _commit,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(hintText: 'Optional instructions'),
      ),
    );
  }
}

class const AiAssistModelDiscoveryState({
  final bool loading = false,
  final String? error,
});
