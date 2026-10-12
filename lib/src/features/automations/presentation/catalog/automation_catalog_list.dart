import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/automation_workspace_runs.dart';
import 'package:alera/src/features/automations/presentation/catalog/automation_catalog_row.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_composer_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _othersGroupKey = '\u0000others';

/// The visible definitions, grouped like the sidebar (by project or section)
/// with one header per group, which the user can collapse. The workspace
/// scope instead lists what is scheduled here and, separately, the runs
/// that used this workspace.
class const AutomationCatalogList({
  required final AsyncValue<List<AutomationRecord>> catalog,
  required final AutomationsLocation location,
  required final AutomationWorkbenchContext names,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(automationsNavigationProvider.notifier);
    final automations = catalog.value;
    final workspaceId = location.scope.kind == AutomationScopeKind.workspace
        ? location.scope.id
        : null;
    if (automations == null) {
      return catalog.hasError
          ? AleraEmptyState(
              icon: AleraIcons.error,
              title: 'Automations Unavailable',
              message: automationErrorMessage(catalog.error),
            )
          : const AleraEmptyState(
              message: 'Loading automations.',
              loading: true,
            );
    }
    final visible = visibleAutomations(
      automations,
      location.scope,
      location.filters,
    );
    Widget row(AutomationRecord automation) => AutomationCatalogRow(
      key: ValueKey<String>(automation.id),
      automation: automation,
      names: names,
      selected: automation.id == location.selectedId,
      onTap: () => navigation.select(automation.id),
      onEdit: () => unawaited(
        showAutomationComposerDialog(
          context,
          ref,
          request: AutomationAuthoringRequest(editId: automation.id),
        ),
      ),
    );
    final groupBy = ref.watch(
      workbenchControllerProvider.select((state) => state.viewPrefs.groupBy),
    );
    final children = <Widget>[
      if (workspaceId != null)
        const AleraSectionHeader(label: 'Scheduled Here'),
      if (visible.isEmpty)
        _EmptyCatalog(
          filtered:
              location.filters.isFiltered ||
              location.scope != AutomationScope.all,
          onClear: () {
            navigation
              ..clearFilters()
              ..setScope(AutomationScope.all);
          },
        )
      else if (workspaceId != null || groupBy == WorkbenchGroupBy.none)
        ...visible.map(row)
      else
        for (final group in groupAutomations(
          visible,
          keyOf: (automation) => groupBy == WorkbenchGroupBy.section
              ? automation.association?.sectionId
              : automation.effectiveProjectId,
          labelOf: (key) => groupBy == WorkbenchGroupBy.section
              ? names.sectionName(key)
              : names.projectName(key),
        ))
          AleraCollapsibleSection(
            key: ValueKey<String>('group:${group.key ?? _othersGroupKey}'),
            title: group.label,
            trailing: AleraBadge(label: '${group.automations.length}'),
            expanded: !location.collapsedGroups.contains(
              group.key ?? _othersGroupKey,
            ),
            onExpandedChanged: (_) =>
                navigation.toggleGroup(group.key ?? _othersGroupKey),
            child: Column(
              crossAxisAlignment: .stretch,
              children: group.automations.map(row).toList(),
            ),
          ),
      if (workspaceId != null)
        AutomationWorkspaceRuns(workspaceId: workspaceId),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      children: children,
    );
  }
}

class const _EmptyCatalog({
  required final bool filtered,
  required final VoidCallback onClear,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => filtered
      ? AleraEmptyState(
          icon: AleraIcons.searchOff,
          title: 'No Matches',
          message: 'No automations match these filters. Clear or adjust them to see other automations.',
          action: TextButton(
            onPressed: onClear,
            child: const Text('Clear Filters'),
          ),
        )
      : const AleraEmptyState(
          icon: AleraIcons.schedule,
          title: 'No Automations Yet',
          message: 'Choose New Automation to schedule a prompt for an agent.',
        );
}
