import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automation_workspace_tags.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_options.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Name, section, tags, setup and cleanup of the workspaces runs create.
/// Only shown for destinations that create one.
class AutomationWorkspaceOptions extends ConsumerStatefulWidget {
  const AutomationWorkspaceOptions({super.key, required this.provider});

  final AutomationComposerControllerProvider provider;

  @override
  ConsumerState<AutomationWorkspaceOptions> createState() =>
      _AutomationWorkspaceOptionsState();
}

class _AutomationWorkspaceOptionsState
    extends ConsumerState<AutomationWorkspaceOptions> {
  late final TextEditingController _nameTemplate = TextEditingController(
    text: ref.read(widget.provider).draft.nameTemplate,
  );

  @override
  void dispose() {
    _nameTemplate.dispose();
    super.dispose();
  }

  void _update(AutomationDraft Function(AutomationDraft draft) change) =>
      ref.read(widget.provider.notifier).update(change);

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(widget.provider.select((state) => state.draft));
    final names = ref.watch(automationWorkbenchContextProvider);
    final sectionId = draft.workspaceSectionId;
    final sections = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry(value: null, label: 'No Section'),
      for (final section in names.sections)
        AleraDropdownFieldEntry(value: section.id, label: section.name),
    ];
    return AutomationOptionFields(
      children: <Widget>[
        AleraTextField(
          controller: _nameTemplate,
          labelText: 'Workspace Name Template',
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (value) =>
              _update((current) => current.copyWith(nameTemplate: value)),
        ),
        AleraDropdownField<String?>(
          labelText: 'Section',
          value: sections.any((entry) => entry.value == sectionId)
              ? sectionId
              : null,
          hintText: 'No Section',
          entries: sections,
          onChanged: (value) => _update(
            (current) => current.withTargetField(.workspaceSectionId, value),
          ),
        ),
        _WorkspaceTags(
          selected: draft.workspaceTagIds,
          onChanged: (ids) =>
              _update((current) => current.copyWith(workspaceTagIds: ids)),
        ),
        if (draft.offersWorkspaceSetup)
          AutomationPolicyField(
            label: 'Workspace Setup',
            value: draft.setupPolicy,
            options: automationSetupPolicies,
            onChanged: (value) =>
                _update((current) => current.copyWith(setupPolicy: value)),
          ),
        if (draft.offersCleanup)
          AutomationPolicyField(
            label: 'Cleanup',
            value: draft.cleanupPolicy,
            options: automationCleanupPolicies,
            onChanged: (value) =>
                _update((current) => current.copyWith(cleanupPolicy: value)),
          ),
      ],
    );
  }
}

class const _WorkspaceTags({
  required final List<String> selected,
  required final ValueChanged<List<String>> onChanged,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final tags = ref.watch(automationWorkspaceTagsProvider);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text('Workspace Tags', style: muted),
        const SizedBox(height: AleraTokens.space6),
        switch (tags) {
          AsyncData(:final value) when value.isEmpty => Text(
            'No workspace tags yet. Add them from a workspace menu in the sidebar.',
            style: muted,
          ),
          AsyncData(:final value) => Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final tag in value)
                AleraChip(
                  label: tag.name,
                  leading: selected.contains(tag.id)
                      ? AleraIcons.check
                      : AleraIcons.tag,
                  tooltip: selected.contains(tag.id)
                      ? 'Remove ${tag.name}'
                      : 'Add ${tag.name}',
                  onTap: () => onChanged(
                    selected.contains(tag.id)
                        ? selected.where((id) => id != tag.id).toList()
                        : <String>[...selected, tag.id],
                  ),
                ),
            ],
          ),
          AsyncError() => Text(
            'Could not load workspace tags. Check the runtime connection and try again.',
            style: muted,
          ),
          _ => Text('Loading tags...', style: muted),
        },
      ],
    );
  }
}
