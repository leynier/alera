import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [filters] with the given fields replaced.
AutomationCatalogFilters mobileAutomationFilters(
  AutomationCatalogFilters filters, {
  String? search,
  String? Function()? projectId,
  String? Function()? hostId,
  String? Function()? profileId,
  AutomationBucket? Function()? bucket,
}) => AutomationCatalogFilters(
  search: search ?? filters.search,
  projectId: projectId == null ? filters.projectId : projectId(),
  hostId: hostId == null ? filters.hostId : hostId(),
  profileId: profileId == null ? filters.profileId : profileId(),
  bucket: bucket == null ? filters.bucket : bucket(),
);

/// Project, Agent Profile and Host filters. Every picker shows names, never
/// ids, and Host only appears once automations run on more than one host.
Future<void> showMobileAutomationFilters(
  BuildContext context, {
  required String hostId,
  required List<AutomationRecord> automations,
  required MobileAutomationContext names,
}) => showModalBottomSheet<void>(
  context: context,
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
    final filters = ref
        .watch(mobileAutomationListControllerProvider(hostId))
        .filters;
    final controller = ref.read(
      mobileAutomationListControllerProvider(hostId).notifier,
    );
    final profileIds = <String>{
      for (final automation in automations) ?automation.agentProfileId,
    };
    final hostIds = <String>{
      for (final automation in automations) ?automation.targetHostId,
    };
    return SafeArea(
      child: Padding(
        padding: AleraTokens.pagePadding,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text('Filters', style: Theme.of(context).textTheme.titleMedium),
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
              onChanged: (value) => controller.setFilters(
                mobileAutomationFilters(filters, projectId: () => value),
              ),
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
              onChanged: (value) => controller.setFilters(
                mobileAutomationFilters(filters, profileId: () => value),
              ),
            ),
            if (hostIds.length > 1 || filters.hostId != null) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceMd),
              AleraDropdownField<String?>(
                labelText: 'Host',
                value: filters.hostId,
                entries: <AleraDropdownFieldEntry<String?>>[
                  const AleraDropdownFieldEntry(
                    value: null,
                    label: 'All Hosts',
                  ),
                  for (final host in hostIds)
                    AleraDropdownFieldEntry(
                      value: host,
                      label: names.hostName(host),
                    ),
                ],
                onChanged: (value) => controller.setFilters(
                  mobileAutomationFilters(filters, hostId: () => value),
                ),
              ),
            ],
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
