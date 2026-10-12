import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera_mobile/src/features/automations/presentation/automation_detail_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen_catalog.dart';
import 'package:alera_mobile/src/features/automations/presentation/authoring/mobile_automation_authoring_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_filters_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens an automation's detail, optionally at one of its runs.
Future<void> openAutomationDetail(
  BuildContext context,
  String hostId,
  String id, {
  String? runId,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => AutomationDetailScreen(
      hostId: hostId,
      automationId: id,
      initialRunId: runId,
    ),
  ),
);

/// New Automation from the list's current scope; a workspace scope becomes
/// the origin, never the execution target.
Future<void> startAutomationAuthoring(
  BuildContext context,
  WidgetRef ref,
  String hostId,
) async {
  final scope = ref.read(mobileAutomationListControllerProvider(hostId)).scope;
  final saved = await showMobileAutomationAuthoring(
    context,
    hostId: hostId,
    originWorkspaceId: scope.kind == AutomationScopeKind.workspace
        ? scope.id
        : null,
  );
  if (saved != null && context.mounted) {
    unawaited(openAutomationDetail(context, hostId, saved.id));
  }
}

/// Whether the catalog never loaded, so there is nothing to act on.
bool automationsUnavailable(WidgetRef ref, String hostId) {
  final catalog = ref.watch(mobileAutomationCatalogProvider(hostId));
  return catalog.hasError && catalog.value == null;
}

/// Filters and the catalog menu, kept in the Activity app bar while
/// Automations is open.
class const AutomationsSectionActions({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final automations =
        ref.watch(mobileAutomationCatalogProvider(hostId)).value ??
        const <AutomationRecord>[];
    final names =
        ref.watch(mobileAutomationContextProvider(hostId)).value ??
        const MobileAutomationContext();
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        IconButton(
          tooltip: 'Filters',
          icon: const Icon(AleraIcons.filter),
          onPressed: () => unawaited(
            showMobileAutomationFilters(
              context,
              hostId: hostId,
              automations: automations,
              names: names,
            ),
          ),
        ),
        AutomationsCatalogMenu(hostId: hostId),
      ],
    );
  }
}

/// Schedules of the host and their runs. The Automations part of Activity.
class const AutomationsSectionBody({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(mobileAutomationCatalogProvider(hostId));
    final list = ref.watch(mobileAutomationListControllerProvider(hostId));
    final controller = ref.read(
      mobileAutomationListControllerProvider(hostId).notifier,
    );
    final names =
        ref.watch(mobileAutomationContextProvider(hostId)).value ??
        const MobileAutomationContext();
    final automations = catalog.value ?? const <AutomationRecord>[];
    final visible = visibleAutomations(automations, list.scope, list.filters);
    final counts = automationBucketCounts(automations, list.scope);
    final workspaceScope =
        list.scope.kind == AutomationScopeKind.workspace &&
        list.scope.id != null;
    final filtered =
        list.filters.isFiltered || list.scope != AutomationScope.all;
    return catalog.value == null && catalog.hasError
        ? AutomationsErrorState(error: catalog.error!)
        : catalog.value == null
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () =>
                ref.refresh(mobileAutomationCatalogProvider(hostId).future),
            child: ListView(
              padding: AleraTokens.pagePadding,
              children: <Widget>[
                if (catalog.hasError)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AleraTokens.spaceSm),
                    child: AleraNotice(
                      message: 'Offline. Showing the last list from this host; actions are unavailable until it reconnects.',
                    ),
                  ),
                AleraSearchField(
                  hintText: 'Search Automations',
                  initialValue: list.filters.search,
                  debounce: AleraTokens.durationMid,
                  onChanged: (value) =>
                      controller.setFilters(_withSearch(list.filters, value)),
                ),
                const SizedBox(height: AleraTokens.spaceSm),
                _BucketChips(
                  selected: list.filters.bucket,
                  counts: counts,
                  onSelected: (bucket) =>
                      controller.setFilters(_withBucket(list.filters, bucket)),
                ),
                if (list.scope != AutomationScope.all)
                  Padding(
                    padding: const EdgeInsets.only(top: AleraTokens.spaceSm),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AleraChip(
                        label: _scopeLabel(list.scope, names),
                        onRemove: () =>
                            controller.setScope(AutomationScope.all),
                      ),
                    ),
                  ),
                const SizedBox(height: AleraTokens.spaceSm),
                if (workspaceScope)
                  const AleraSectionHeader(label: 'Scheduled Here'),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AleraTokens.spaceLg),
                    child: Column(
                      children: <Widget>[
                        Text(
                          filtered
                              ? 'No automations match these filters.'
                              : 'No automations on this host yet.',
                          textAlign: .center,
                        ),
                        if (filtered)
                          TextButton(
                            onPressed: controller.clear,
                            child: const Text('Clear Filters'),
                          ),
                      ],
                    ),
                  )
                else
                  for (final automation in visible)
                    _AutomationCard(
                      automation: automation,
                      names: names,
                      onOpen: () => unawaited(
                        openAutomationDetail(context, hostId, automation.id),
                      ),
                    ),
                if (workspaceScope)
                  _WorkspaceRuns(
                    hostId: hostId,
                    workspaceId: list.scope.id!,
                    automations: automations,
                    onOpen: (run) => unawaited(
                      openAutomationDetail(
                        context,
                        hostId,
                        run.automationId,
                        runId: run.id,
                      ),
                    ),
                  ),
                const SizedBox(height: AleraTokens.spaceXxl * 2),
              ],
            ),
          );
  }
}

AutomationCatalogFilters _withSearch(
  AutomationCatalogFilters filters,
  String search,
) => AutomationCatalogFilters(
  search: search,
  projectId: filters.projectId,
  hostId: filters.hostId,
  profileId: filters.profileId,
  tagId: filters.tagId,
  bucket: filters.bucket,
);

AutomationCatalogFilters _withBucket(
  AutomationCatalogFilters filters,
  AutomationBucket? bucket,
) => AutomationCatalogFilters(
  search: filters.search,
  projectId: filters.projectId,
  hostId: filters.hostId,
  profileId: filters.profileId,
  tagId: filters.tagId,
  bucket: bucket,
);

String _scopeLabel(AutomationScope scope, MobileAutomationContext names) =>
    switch (scope.kind) {
      AutomationScopeKind.project => 'Project: ${names.projectName(scope.id)}',
      AutomationScopeKind.section => 'Section: ${names.sectionName(scope.id)}',
      AutomationScopeKind.workspace =>
        'Workspace: ${names.workspaceName(scope.id)}',
      AutomationScopeKind.all => 'All Automations',
    };

class const _BucketChips({
  required final AutomationBucket? selected,
  required final Map<AutomationBucket, int> counts,
  required final ValueChanged<AutomationBucket?> onSelected,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: <Widget>[
        ChoiceChip(
          label: const Text('All'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final bucket in AutomationBucket.values)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.spaceXs),
            child: ChoiceChip(
              label: Text('${bucket.label} (${counts[bucket] ?? 0})'),
              selected: selected == bucket,
              onSelected: (_) => onSelected(bucket),
            ),
          ),
      ],
    ),
  );
}

class const _AutomationCard({
  required final AutomationRecord automation,
  required final MobileAutomationContext names,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = automationStateLabel(automation);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final lastRun = automation.lastRun;
    return Card(
      margin: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            crossAxisAlignment: .start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      automation.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                  if (lastRun != null) ...<Widget>[
                    AleraStatusDot(
                      active: true,
                      color: mobileAutomationToneColor(
                        automationRunStatusLabel(
                          AutomationRunRecord.fromJson(<String, Object?>{
                            'status': lastRun.status,
                          }),
                        ).tone,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.spaceSm),
                  ],
                  AleraBadge(
                    label: state.label,
                    tone: mobileAutomationBadgeTone(state.tone),
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.spaceXs),
              Text(mobileAutomationScheduleLine(automation), style: muted),
              Text(
                mobileAutomationTargetLine(automation, names),
                style: muted,
                maxLines: 2,
                overflow: .ellipsis,
              ),
              if (automation.attention case final attention?)
                Text(
                  attention.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.warning,
                  ),
                ),
              if (automation.createdByAgent)
                Text(
                  'Created by agent ${automation.createdByLabel ?? ''}'.trim(),
                  style: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Runs whose own workspace is this one. Where a run happened never makes its
/// automation belong to the workspace.
class const _WorkspaceRuns({
  required final String hostId,
  required final String workspaceId,
  required final List<AutomationRecord> automations,
  required final ValueChanged<AutomationRunRecord> onOpen,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs =
        ref.watch(mobileAutomationRecentRunsProvider(hostId)).value ??
        const <AutomationRunRecord>[];
    final here = runs
        .where((run) => run.workspaceId == workspaceId)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        const AleraSectionHeader(label: 'Runs In This Workspace'),
        if (here.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AleraTokens.spaceMd),
            child: Text('No automation runs used this workspace recently.'),
          )
        else
          for (final run in here)
            MobileAutomationRunRow(
              run: run,
              automationName: automations
                  .where((item) => item.id == run.automationId)
                  .firstOrNull
                  ?.name,
              onTap: () => onOpen(run),
            ),
      ],
    );
  }
}
