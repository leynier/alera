import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';

class AiTextAgentRow extends StatelessWidget {
  const AiTextAgentRow({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AiTextGenerationAgent value;
  final ValueChanged<AiTextGenerationAgent> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Agent',
      description: 'CLI used for generated source control text.',
      child: AleraDropdownField<AiTextGenerationAgent>(
        key: ValueKey<String>('ai-text-agent-${value.key}'),
        value: value,
        entries: <AleraDropdownFieldEntry<AiTextGenerationAgent>>[
          for (final agent in AiTextGenerationAgent.values)
            AleraDropdownFieldEntry<AiTextGenerationAgent>(
              value: agent,
              label: agent.label,
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class AiTextModelRow extends StatelessWidget {
  const AiTextModelRow({
    super.key,
    required this.agent,
    required this.models,
    required this.value,
    required this.canDiscoverModels,
    required this.discovering,
    required this.discoveryError,
    required this.onRefreshModels,
    required this.onChanged,
  });

  final AiTextGenerationAgent agent;
  final List<AiTextModel> models;
  final String value;
  final bool canDiscoverModels;
  final bool discovering;
  final String? discoveryError;
  final VoidCallback? onRefreshModels;
  final ValueChanged<String> onChanged;

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
              key: ValueKey<String>('ai-text-model-${agent.key}-$value'),
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

class AiTextThinkingRow extends StatelessWidget {
  const AiTextThinkingRow({
    super.key,
    required this.levels,
    required this.value,
    required this.onChanged,
  });

  final List<AiThinkingLevel> levels;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = levels.any((level) => level.id == value)
        ? value
        : levels.first.id;
    return AleraSettingRow(
      title: 'Thinking',
      description: 'Reasoning effort for models that support it.',
      child: AleraDropdownField<String>(
        key: ValueKey<String>('ai-text-thinking-$value'),
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

class InstructionSettingRow extends StatefulWidget {
  const InstructionSettingRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;

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
        minLines: 2,
        maxLines: 4,
        onEditingComplete: _commit,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(hintText: 'Optional instructions'),
      ),
    );
  }
}
