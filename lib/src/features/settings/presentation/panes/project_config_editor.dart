import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:flutter/material.dart';

class ProjectConfigEditor extends StatelessWidget {
  const ProjectConfigEditor({
    super.key,
    required this.project,
    required this.sourceLabel,
    required this.copyRules,
    required this.setupCommands,
    required this.saveError,
    required this.saving,
    required this.updateCopyRule,
    required this.removeCopyRule,
    required this.addCopyRule,
    required this.updateSetupCommand,
    required this.removeSetupCommand,
    required this.addSetupCommand,
    required this.saveOverride,
    required this.useRepoFile,
    this.sourceError,
  });

  final Project project;
  final String sourceLabel;
  final String? sourceError;
  final List<EditableCopyRule> copyRules;
  final List<String> setupCommands;
  final String? saveError;
  final bool saving;
  final void Function(int index, EditableCopyRule rule) updateCopyRule;
  final ValueChanged<int> removeCopyRule;
  final VoidCallback addCopyRule;
  final void Function(int index, String command) updateSetupCommand;
  final ValueChanged<int> removeSetupCommand;
  final VoidCallback addSetupCommand;
  final Future<void> Function(Project project) saveOverride;
  final Future<void> Function()? useRepoFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraSettingsGroup(
          title: project.name,
          description: 'UI Overrides Take Precedence Over Repo Files.',
          children: <Widget>[
            AleraSettingRow(
              title: 'Config Source',
              description: project.repoPath,
              controlWidth: 150,
              child: Align(
                alignment: Alignment.centerRight,
                child: _ProjectConfigSourceBadge(label: sourceLabel),
              ),
            ),
            if (sourceError != null)
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space16),
                child: Text(
                  sourceError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Copy Rules',
          description: 'Files And Directories Copied From The Main Worktree.',
          children: <Widget>[
            if (copyRules.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No Copy Rules')
            else
              for (var i = 0; i < copyRules.length; i += 1)
                _CopyRuleEditorRow(
                  key: ValueKey<String>('copy-rule-$i'),
                  rule: copyRules[i],
                  onChanged: (rule) => updateCopyRule(i, rule),
                  onRemove: () => removeCopyRule(i),
                ),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: addCopyRule,
                  icon: const Icon(AleraIcons.add, size: 16),
                  label: const Text('Add Copy Rule'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Setup Commands',
          description: 'Commands Run From The New Linked Workspace.',
          children: <Widget>[
            if (setupCommands.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No Setup Commands')
            else
              for (var i = 0; i < setupCommands.length; i += 1)
                _SetupCommandEditorRow(
                  key: ValueKey<String>('setup-command-$i'),
                  command: setupCommands[i],
                  onChanged: (command) => updateSetupCommand(i, command),
                  onRemove: () => removeSetupCommand(i),
                ),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: addSetupCommand,
                  icon: const Icon(AleraIcons.add, size: 16),
                  label: const Text('Add Setup Command'),
                ),
              ),
            ),
          ],
        ),
        if (saveError != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Text(
            saveError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
        const SizedBox(height: AleraTokens.space16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            if (useRepoFile != null) ...<Widget>[
              OutlinedButton(
                onPressed: saving ? null : useRepoFile,
                child: const Text('Use Repo File'),
              ),
            ],
            FilledButton.icon(
              onPressed: saving ? null : () => saveOverride(project),
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AleraIcons.save, size: 16),
              label: Text(saving ? 'Saving' : 'Save Override'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CopyRuleEditorRow extends StatelessWidget {
  const _CopyRuleEditorRow({
    super.key,
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final EditableCopyRule rule;
  final ValueChanged<EditableCopyRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('copy-rule-from-field'),
              value: rule.from,
              labelText: 'From',
              hintText: '.env',
              onChanged: (value) => onChanged(rule.copyWith(from: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('copy-rule-to-field'),
              value: rule.to,
              labelText: 'To',
              hintText: 'Defaults To From',
              onChanged: (value) => onChanged(rule.copyWith(to: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Tooltip(
            message: 'Overwrite Existing Destination',
            child: Checkbox(
              value: rule.overwrite,
              onChanged: (value) =>
                  onChanged(rule.copyWith(overwrite: value ?? false)),
            ),
          ),
          AleraIconButton(
            tooltip: 'Remove Copy Rule',
            onPressed: onRemove,
            icon: AleraIcons.delete,
          ),
        ],
      ),
    );
  }
}

class _SetupCommandEditorRow extends StatelessWidget {
  const _SetupCommandEditorRow({
    super.key,
    required this.command,
    required this.onChanged,
    required this.onRemove,
  });

  final String command;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('setup-command-field'),
              value: command,
              labelText: 'Command',
              hintText: 'make bootstrap',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          AleraIconButton(
            tooltip: 'Remove Setup Command',
            onPressed: onRemove,
            icon: AleraIcons.delete,
          ),
        ],
      ),
    );
  }
}

class _ProjectConfigTextField extends StatefulWidget {
  const _ProjectConfigTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.hintText,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? labelText;
  final String? hintText;

  @override
  State<_ProjectConfigTextField> createState() =>
      _ProjectConfigTextFieldState();
}

class _ProjectConfigTextFieldState extends State<_ProjectConfigTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_ProjectConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: _controller,
      labelText: widget.labelText,
      hintText: widget.hintText,
      onChanged: widget.onChanged,
    );
  }
}

class _ProjectConfigSourceBadge extends StatelessWidget {
  const _ProjectConfigSourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AleraTokens.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectConfigEmptyRow extends StatelessWidget {
  const _ProjectConfigEmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}

class EditableCopyRule {
  const EditableCopyRule({
    this.from = '',
    this.to = '',
    this.overwrite = false,
  });

  final String from;
  final String to;
  final bool overwrite;

  EditableCopyRule copyWith({String? from, String? to, bool? overwrite}) {
    return EditableCopyRule(
      from: from ?? this.from,
      to: to ?? this.to,
      overwrite: overwrite ?? this.overwrite,
    );
  }
}

String projectConfigSignature(ProjectConfig config) {
  final buffer = StringBuffer();
  for (final rule in config.worktree.copy) {
    buffer
      ..write(rule.from)
      ..write('\u{1f}')
      ..write(rule.to ?? '')
      ..write('\u{1f}')
      ..write(rule.overwrite)
      ..write('\u{1e}');
  }
  buffer.write('\u{1d}');
  for (final command in config.worktree.setup) {
    buffer
      ..write(command)
      ..write('\u{1e}');
  }
  return buffer.toString();
}
