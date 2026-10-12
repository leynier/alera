import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_location.dart';
import 'package:alera/src/features/automations/domain/automation_authoring_request.dart';
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

/// Opens New Automation from the scope the catalog is looking at.
Future<void> startAutomationAuthoringFromSection(
  BuildContext context,
  WidgetRef ref,
) async {
  final scope = ref.read(activityNavigationProvider).automations.scope;
  await showAutomationAuthoringDialog(
    context,
    ref,
    request: _requestForScope(scope),
  );
}

/// The Automations section of Activity.
class AutomationsSection extends ConsumerStatefulWidget {
  const AutomationsSection({super.key});

  @override
  ConsumerState<AutomationsSection> createState() => _AutomationsSectionState();
}

class _AutomationsSectionState extends ConsumerState<AutomationsSection> {
  int _handledAuthoring = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartAuthoring());
  }

  void _maybeStartAuthoring() {
    if (!mounted) return;
    final location = ref.read(activityNavigationProvider).automations;
    final request = location.authoring;
    if (request == null || location.authoringSequence == _handledAuthoring) {
      return;
    }
    _handledAuthoring = location.authoringSequence;
    ref.read(activityNavigationProvider.notifier).consumeAuthoring();
    unawaited(showAutomationAuthoringDialog(context, ref, request: request));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      activityNavigationProvider.select(
        (value) => value.automations.authoringSequence,
      ),
      (_, _) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeStartAuthoring(),
      ),
    );
    final location = ref.watch(
      activityNavigationProvider.select((value) => value.automations),
    );
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
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _RuntimeAvailabilityNotice(
                  unreachable: catalog.hasError,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              const AutomationCatalogMenu(),
            ],
          ),
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
    );
  }
}

AutomationAuthoringRequest _requestForScope(AutomationScope scope) =>
    switch (scope.kind) {
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
    final navigation = ref.read(activityNavigationProvider.notifier);
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
      onScope: navigation.setAutomationScope,
      onFilters: navigation.setAutomationFilters,
      onClear: () {
        navigation.clearAutomationFilters();
        navigation.setAutomationScope(AutomationScope.all);
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
            onTap: () => navigation.selectAutomation(automation.id),
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
