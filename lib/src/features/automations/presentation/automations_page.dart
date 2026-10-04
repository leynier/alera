import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_dialog.dart';
import 'package:alera/src/features/automations/presentation/automation_catalog_actions.dart';
import 'package:alera/src/features/automations/presentation/automation_catalog_filters.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_view.dart';
import 'package:alera/src/features/automations/presentation/automation_list_tile.dart';
import 'package:alera/src/features/automations/presentation/automation_workspace_runs.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Automations surface of the shell, opened like the Run Board: it keeps
/// the workbench mounted underneath and returns to it unchanged.
class AutomationsPage extends ConsumerStatefulWidget {
  const AutomationsPage({super.key, this.onReturnToWorkspace});

  final VoidCallback? onReturnToWorkspace;

  @override
  ConsumerState<AutomationsPage> createState() => _AutomationsPageState();
}

class _AutomationsPageState extends ConsumerState<AutomationsPage> {
  int _handledAuthoring = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartAuthoring());
  }

  void _maybeStartAuthoring() {
    if (!mounted) return;
    final location = ref.read(automationsNavigationProvider);
    final request = location.authoring;
    if (request == null || location.authoringSequence == _handledAuthoring) {
      return;
    }
    _handledAuthoring = location.authoringSequence;
    ref.read(automationsNavigationProvider.notifier).consumeAuthoring();
    unawaited(showAutomationAuthoringDialog(context, ref, request: request));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      automationsNavigationProvider.select((value) => value.authoringSequence),
      (_, _) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeStartAuthoring(),
      ),
    );
    final location = ref.watch(automationsNavigationProvider);
    final navigation = ref.read(automationsNavigationProvider.notifier);
    final catalog = ref.watch(automationCatalogProvider);
    final names = ref.watch(automationWorkbenchContextProvider);
    final automations = catalog.value ?? const <AutomationRecord>[];
    final selected = automations
        .where((item) => item.id == location.selectedId)
        .firstOrNull;
    final master = _AutomationCatalogPane(
      catalog: catalog,
      location: location,
      names: names,
    );
    final detail = selected == null
        ? AleraEmptyState(
            icon: AleraIcons.checks,
            title: location.selectedId == null
                ? 'Select An Automation'
                : 'Automation Unavailable',
            message: location.selectedId == null
                ? 'Inspect schedules, targets, runs and recovery. Opening this page does not change your workspace.'
                : 'It may have been deleted. Choose another automation.',
          )
        : AutomationDetailView(
            key: ValueKey<String>(selected.id),
            automation: selected,
            selectedRunId: location.selectedRunId,
          );
    return FocusTraversalGroup(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Wrap(
              spacing: AleraTokens.space12,
              runSpacing: AleraTokens.space8,
              crossAxisAlignment: .center,
              children: <Widget>[
                const AleraAppMenuButton(),
                Text(
                  'Automations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                FilledButton.icon(
                  onPressed: () => unawaited(
                    showAutomationAuthoringDialog(
                      context,
                      ref,
                      request: _requestForScope(location.scope, names),
                    ),
                  ),
                  icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
                  label: const Text('New Automation'),
                ),
                TextButton.icon(
                  onPressed: widget.onReturnToWorkspace ?? navigation.close,
                  icon: const Icon(AleraIcons.back),
                  label: const Text('Return To Workspace'),
                ),
                const AutomationCatalogMenu(),
                IconButton(
                  tooltip: 'Refresh Automations',
                  icon: const Icon(AleraIcons.refresh),
                  onPressed: () => ref.invalidate(automationCatalogProvider),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            _RuntimeAvailabilityNotice(unreachable: catalog.hasError),
            const SizedBox(height: AleraTokens.space8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  if (constraints.maxWidth <
                      AleraTokens.wideContentBreakpoint * scale) {
                    return selected == null ? master : detail;
                  }
                  return AleraMasterDetail(
                    masterTitle: 'Automations',
                    masterWidth: AleraTokens.sidebarDefaultWidth,
                    masterMaxWidth: AleraTokens.masterDetailMaxWidth,
                    master: master,
                    detail: detail,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

AutomationAuthoringRequest _requestForScope(
  AutomationScope scope,
  AutomationWorkbenchContext names,
) => switch (scope.kind) {
  AutomationScopeKind.workspace => AutomationAuthoringRequest(
    originWorkspaceId: scope.id,
  ),
  AutomationScopeKind.project => AutomationAuthoringRequest(
    projectId: scope.id,
  ),
  _ => const AutomationAuthoringRequest(),
};

/// The runtime owns schedules. Nothing here starts it or changes autostart.
class const _RuntimeAvailabilityNotice({required final bool unreachable})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (unreachable) {
      return const AleraInlineNotice(
        tone: .warning,
        message: 'The Alera runtime is not reachable. Automations run only while Alera is open or a runtime started with alera runtime start is running.',
      );
    }
    return Text(
      'Automations run while the Alera runtime is running. Interrupted runs recover when it starts again.',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}

class const _AutomationCatalogPane({
  required final AsyncValue<List<AutomationRecord>> catalog,
  required final AutomationsLocation location,
  required final AutomationWorkbenchContext names,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigation = ref.read(automationsNavigationProvider.notifier);
    final automations = catalog.value ?? const <AutomationRecord>[];
    final visible = visibleAutomations(
      automations,
      location.scope,
      location.filters,
    );
    final groupBy = ref.watch(
      workbenchControllerProvider.select((state) => state.viewPrefs.groupBy),
    );
    final tags = ref.watch(automationTagNamesProvider).value ?? const {};
    final filtersBar = AutomationCatalogFiltersBar(
      scope: location.scope,
      filters: location.filters,
      counts: automationBucketCounts(automations, location.scope),
      automations: automations,
      context: names,
      tags: tags,
      onScope: navigation.setScope,
      onFilters: navigation.setFilters,
      onClear: () {
        navigation.clearFilters();
        navigation.setScope(AutomationScope.all);
      },
    );
    final workspaceScope =
        location.scope.kind == AutomationScopeKind.workspace &&
        location.scope.id != null;
    final rows = <Widget>[
      filtersBar,
      if (workspaceScope) const AleraSectionHeader(label: 'Scheduled Here'),
    ];
    if (catalog.value == null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: catalog.hasError
              ? Text('Automations are unavailable: ${catalog.error}')
              : const Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (visible.isEmpty) {
      final filtered =
          location.filters.isFiltered || location.scope != AutomationScope.all;
      rows.add(
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Text(
            filtered
                ? 'No automations match these filters. Clear or adjust them to see other automations.'
                : 'No automations yet. Choose New Automation to schedule an agent.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    } else {
      String? currentGroup;
      for (final automation in visible) {
        final group = workspaceScope
            ? null
            : switch (groupBy) {
                WorkbenchGroupBy.project => names.projectName(
                  automation.effectiveProjectId,
                ),
                WorkbenchGroupBy.section =>
                  automation.association?.sectionId == null
                      ? 'Others'
                      : names.sectionName(automation.association?.sectionId),
                WorkbenchGroupBy.none => null,
              };
        if (group != null && group != currentGroup) {
          currentGroup = group;
          rows.add(AleraSectionHeader(label: group));
        }
        rows.add(
          AutomationListTile(
            automation: automation,
            names: names,
            selected: automation.id == location.selectedId,
            onTap: () => navigation.select(automation.id),
          ),
        );
      }
    }
    if (workspaceScope) {
      rows.add(AutomationWorkspaceRuns(workspaceId: location.scope.id!));
    }
    return ListView(children: rows);
  }
}
