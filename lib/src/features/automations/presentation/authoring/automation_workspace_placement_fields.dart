import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automation_workspace_tags.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Section and tags of each workspace a run creates, so automation work lands
/// where the user files it instead of in Others.
class const AutomationWorkspacePlacementFields({
  required final AutomationAuthoringControllerProvider provider,
  required final AutomationDraft draft,
  required final AutomationWorkbenchContext names,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final controller = ref.read(provider.notifier);
    final tags = ref.watch(automationWorkspaceTagsProvider);
    final sectionId = draft.workspaceSectionId;
    final sections = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry(value: null, label: 'No Section'),
      for (final section in names.sections)
        AleraDropdownFieldEntry(value: section.id, label: section.name),
    ];
    final selected = draft.workspaceTagIds.toSet();
    void toggle(String id) => controller.update(
      (current) => current.copyWith(
        workspaceTagIds: selected.contains(id)
            ? current.workspaceTagIds.where((item) => item != id).toList()
            : <String>[...current.workspaceTagIds, id],
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text('New Workspaces', style: theme.textTheme.titleSmall),
        const SizedBox(height: AleraTokens.space4),
        Text(
          'Each workspace a run creates gets these tags and lands in this section.',
          style: muted,
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraDropdownField<String?>(
          labelText: 'Section',
          value: sections.any((entry) => entry.value == sectionId)
              ? sectionId
              : null,
          hintText: 'No Section',
          entries: sections,
          onChanged: (value) => controller.update(
            (current) => current.withTargetField(.workspaceSectionId, value),
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        Text('Tags', style: muted),
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
                  onTap: () => toggle(tag.id),
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
