import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter/material.dart';

class const ProjectConfigEditor({
  super.key,
  required final Project project,
  required final String sourceLabel,
  required final List<EditableCopyRule> copyRules,
  required final List<String> setupCommands,
  required final String promptAppend,
  required final ValueChanged<String> onPromptAppendChanged,
  required final String? saveError,
  required final bool saving,
  required final void Function(int index, EditableCopyRule rule) updateCopyRule,
  required final ValueChanged<int> removeCopyRule,
  required final VoidCallback addCopyRule,
  required final void Function(int index, String command) updateSetupCommand,
  required final ValueChanged<int> removeSetupCommand,
  required final VoidCallback addSetupCommand,
  required final Future<void> Function(Project project) saveOverride,
  required final Future<void> Function()? useRepoFile,
  required final GitHostingProvider? gitHostingProvider,
  required final ValueChanged<GitHostingProvider?> onGitHostingProviderChanged,
  final String? sourceError,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraSettingsGroup(
          title: project.name,
          description: 'UI overrides take precedence over repo files.',
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
          title: 'New Workspace',
          description:
              'Project instructions appended to prompts that start an agent.',
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: _ProjectConfigTextField(
                value: promptAppend,
                labelText: 'Prompt Append',
                hintText: 'Add project-specific agent instructions',
                minLines: 3,
                maxLines: 6,
                onChanged: onPromptAppendChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Pull Requests',
          description:
              'Git hosting provider used for pull requests and checks.',
          children: <Widget>[
            AleraSettingRow(
              title: 'Hosting Provider',
              description: 'Auto-detect uses public hosts. Select GitHub for GitHub Enterprise Server.',
              child: AleraDropdownField<GitHostingProvider?>(
                value: gitHostingProvider,
                onChanged: onGitHostingProviderChanged,
                entries: <AleraDropdownFieldEntry<GitHostingProvider?>>[
                  const AleraDropdownFieldEntry<GitHostingProvider?>(
                    value: null,
                    label: 'Auto-Detect',
                  ),
                  for (final provider in GitHostingProvider.values)
                    AleraDropdownFieldEntry<GitHostingProvider?>(
                      value: provider,
                      label: provider.label,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Copy Rules',
          description: 'Files copied from the main worktree. Gitignored matches from .worktreeinclude are copied too.',
          children: <Widget>[
            if (copyRules.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No copy rules')
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
          description: 'Commands run from the new linked workspace.',
          children: <Widget>[
            if (setupCommands.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No setup commands')
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
          alignment: .end,
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

class const _CopyRuleEditorRow({
  super.key,
  required final EditableCopyRule rule,
  required final ValueChanged<EditableCopyRule> onChanged,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        crossAxisAlignment: .center,
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
              hintText: 'Defaults to from',
              onChanged: (value) => onChanged(rule.copyWith(to: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Tooltip(
            message: 'Overwrite existing destination',
            child: AleraCheckbox(
              value: rule.overwrite,
              onChanged: (value) => onChanged(rule.copyWith(overwrite: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
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

class const _SetupCommandEditorRow({
  super.key,
  required final String command,
  required final ValueChanged<String> onChanged,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
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

class const _ProjectConfigTextField({
  super.key,
  required final String value,
  required final ValueChanged<String> onChanged,
  final String? labelText,
  final String? hintText,
  final int? minLines,
  final int? maxLines = 1,
}) extends StatefulWidget {
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
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
    );
  }
}

class const _ProjectConfigSourceBadge({required final String label})
    extends StatelessWidget {
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
          fontWeight: .w600,
        ),
      ),
    );
  }
}

class const _ProjectConfigEmptyRow({required final String message})
    extends StatelessWidget {
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

class const EditableCopyRule({
  final String from = '',
  final String to = '',
  final bool overwrite = false,
}) {
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
  buffer
    ..write('\u{1d}')
    ..write(config.gitHostingProvider?.name ?? '')
    ..write('\u{1d}')
    ..write(config.newWorkspace.promptAppend);
  return buffer.toString();
}
