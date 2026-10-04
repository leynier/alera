import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scope and named filters. Every picker shows names, never ids.
Future<void> showMobileAutomationFilters(
  BuildContext context, {
  required String hostId,
  required List<AutomationRecord> automations,
  required MobileAutomationContext names,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) =>
      _FiltersSheet(hostId: hostId, automations: automations, names: names),
);

class const _FiltersSheet({
  required final String hostId,
  required final List<AutomationRecord> automations,
  required final MobileAutomationContext names,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileAutomationListControllerProvider(hostId));
    final controller = ref.read(
      mobileAutomationListControllerProvider(hostId).notifier,
    );
    final filters = state.filters;
    AutomationCatalogFilters copy({
      String? Function()? projectId,
      String? Function()? profileId,
    }) => AutomationCatalogFilters(
      search: filters.search,
      projectId: projectId == null ? filters.projectId : projectId(),
      hostId: filters.hostId,
      profileId: profileId == null ? filters.profileId : profileId(),
      tagId: filters.tagId,
      bucket: filters.bucket,
    );
    final profileIds = <String>{
      for (final automation in automations) ?automation.agentProfileId,
    };
    final scopes = <AleraDropdownFieldEntry<AutomationScope>>[
      const AleraDropdownFieldEntry(
        value: AutomationScope.all,
        label: 'All Automations',
      ),
      for (final project in names.projects)
        AleraDropdownFieldEntry(
          value: AutomationScope(kind: .project, id: project.id),
          label: 'Project: ${project.name}',
        ),
      for (final section in names.sections)
        AleraDropdownFieldEntry(
          value: AutomationScope(kind: .section, id: section.id),
          label: 'Section: ${section.name}',
        ),
      for (final workspace in names.workspaces)
        AleraDropdownFieldEntry(
          value: AutomationScope(kind: .workspace, id: workspace.id),
          label: 'Workspace: ${workspace.name}',
        ),
    ];
    if (!scopes.any((entry) => entry.value == state.scope)) {
      scopes.add(
        AleraDropdownFieldEntry(
          value: state.scope,
          label: switch (state.scope.kind) {
            AutomationScopeKind.project => 'Unavailable Project',
            AutomationScopeKind.section => 'Unavailable Section',
            _ => 'Unavailable Workspace',
          },
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: AleraTokens.pagePadding,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDropdownField<AutomationScope>(
              labelText: 'Scope',
              value: state.scope,
              entries: scopes,
              filterable: true,
              onChanged: controller.setScope,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            AleraDropdownField<String?>(
              labelText: 'Project',
              value: filters.projectId,
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry(
                  value: null,
                  label: 'All Projects',
                ),
                for (final project in names.projects)
                  AleraDropdownFieldEntry(
                    value: project.id,
                    label: project.name,
                  ),
              ],
              onChanged: (value) =>
                  controller.setFilters(copy(projectId: () => value)),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            AleraDropdownField<String?>(
              labelText: 'Agent Profile',
              value: filters.profileId,
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry(
                  value: null,
                  label: 'All Agent Profiles',
                ),
                for (final profile in profileIds)
                  AleraDropdownFieldEntry(
                    value: profile,
                    label: names.profileName(profile),
                  ),
              ],
              onChanged: (value) =>
                  controller.setFilters(copy(profileId: () => value)),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            TextButton(
              onPressed: controller.clear,
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
