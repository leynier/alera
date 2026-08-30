import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
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
      description: 'CLI used for AI Assist jobs.',
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
    final known = models.any((model) => model.id == value);
    if (!known) {
      return SettingsTextRow(
        title: 'Model',
        description: 'Model passed to ${agent.label}.',
        value: value,
        onChanged: onChanged,
      );
    }
    return AleraSettingRow(
      title: 'Model',
      description: discoveryError == null
          ? 'Model passed to ${agent.label}.'
          : discoveryError!,
      child: Row(
        children: <Widget>[
          Expanded(
            child: AleraDropdownField<String>(
              key: ValueKey<String>('ai-assist-model-${agent.key}-$value'),
              value: value,
              entries: <AleraDropdownFieldEntry<String>>[
                for (final model in models)
                  AleraDropdownFieldEntry<String>(
                    value: model.id,
                    label: model.label,
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
          if (canDiscoverModels) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Refresh models',
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
  required final String value,
  required final ValueChanged<String> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final selected = levels.any((level) => level.id == value)
        ? value
        : levels.first.id;
    return AleraSettingRow(
      title: 'Reasoning',
      description: 'Reasoning effort for models that support it.',
      child: AleraDropdownField<String>(
        key: ValueKey<String>('ai-assist-$controlKey-$value'),
        value: selected,
        entries: <AleraDropdownFieldEntry<String>>[
          for (final level in levels)
            AleraDropdownFieldEntry<String>(
              value: level.id,
              label: level.label,
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
    final entries = <AiAssistModel>[
      ...models,
      if (selected != null &&
          selected.isNotEmpty &&
          !models.any((model) => model.id == selected))
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
                    label: model.label,
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
