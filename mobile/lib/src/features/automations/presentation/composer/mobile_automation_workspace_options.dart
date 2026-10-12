import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Name, section, tags, setup and cleanup of the workspaces runs create.
/// Only shown for destinations that create one.
class MobileAutomationWorkspaceOptions extends ConsumerStatefulWidget {
  const MobileAutomationWorkspaceOptions({
    super.key,
    required this.provider,
    required this.hostId,
  });

  final MobileAutomationComposerControllerProvider provider;
  final String hostId;

  @override
  ConsumerState<MobileAutomationWorkspaceOptions> createState() =>
      _MobileAutomationWorkspaceOptionsState();
}

class _MobileAutomationWorkspaceOptionsState
    extends ConsumerState<MobileAutomationWorkspaceOptions> {
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
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
        const MobileAutomationContext();
    final sectionId = draft.workspaceSectionId;
    final sections = <AleraDropdownFieldEntry<String?>>[
      const AleraDropdownFieldEntry(value: null, label: 'No Section'),
      for (final section in names.sections)
        AleraDropdownFieldEntry(value: section.id, label: section.name),
    ];
    final selectedTags = draft.workspaceTagIds;
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return MobileAutomationOptionFields(
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
        Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text('Workspace Tags', style: muted),
            const SizedBox(height: AleraTokens.space6),
            if (names.tags.isEmpty)
              Text(
                'No workspace tags yet. Add them from a workspace menu.',
                style: muted,
              )
            else
              Wrap(
                spacing: AleraTokens.spaceSm,
                runSpacing: AleraTokens.spaceSm,
                children: <Widget>[
                  for (final tag in names.tags)
                    AleraChip(
                      label: tag.name,
                      leading: selectedTags.contains(tag.id)
                          ? AleraIcons.check
                          : AleraIcons.tag,
                      onTap: () => _update(
                        (current) => current.copyWith(
                          workspaceTagIds: selectedTags.contains(tag.id)
                              ? selectedTags
                                    .where((id) => id != tag.id)
                                    .toList()
                              : <String>[...selectedTags, tag.id],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        if (draft.offersWorkspaceSetup)
          MobileAutomationPolicyField(
            label: 'Workspace Setup',
            value: draft.setupPolicy,
            options: automationSetupPolicies,
            onChanged: (value) =>
                _update((current) => current.copyWith(setupPolicy: value)),
          ),
        if (draft.offersCleanup)
          MobileAutomationPolicyField(
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
