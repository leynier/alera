import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/automation_detail_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/catalog/mobile_automation_card.dart';
import 'package:alera_mobile/src/features/automations/presentation/catalog/mobile_automation_workspace_runs.dart';
import 'package:alera_mobile/src/features/automations/presentation/composer/mobile_automation_composer_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_filters_sheet.dart';
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

/// New Automation from the list's current scope; a workspace scope seeds the
/// composer's destination. Saving stays on the list, where the new
/// automation shows up.
Future<void> startAutomationAuthoring(
  BuildContext context,
  WidgetRef ref,
  String hostId,
) async {
  final scope = ref.read(mobileAutomationListControllerProvider(hostId)).scope;
  await showMobileAutomationComposer(
    context,
    hostId: hostId,
    originWorkspaceId: scope.kind == AutomationScopeKind.workspace
        ? scope.id
        : null,
  );
}

/// Whether the catalog never loaded, so there is nothing to act on.
bool automationsUnavailable(WidgetRef ref, String hostId) =>
    ref.watch(mobileAutomationCatalogProvider(hostId)).value == null;

/// Filters, kept in the Activity app bar while Automations is open.
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
    return IconButton(
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
    );
  }
}

/// The automations of one host, grouped by project. The Automations part of
/// Activity.
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
    final filters = list.filters;
    final visible = visibleAutomations(automations, list.scope, filters);
    final counts = automationBucketCounts(automations, list.scope);
    final attention = counts[AutomationBucket.needsAttention] ?? 0;
    final workspaceId = list.scope.kind == AutomationScopeKind.workspace
        ? list.scope.id
        : null;
    final filtered = filters.isFiltered || list.scope != AutomationScope.all;
    Widget card(AutomationRecord automation) => MobileAutomationCard(
      key: ValueKey<String>(automation.id),
      automation: automation,
      names: names,
      onOpen: () =>
          unawaited(openAutomationDetail(context, hostId, automation.id)),
    );
    if (catalog.value == null && catalog.hasError) {
      return AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Automations Unavailable',
        message: catalog.error is UnsupportedError
            ? 'Update the runtime to manage automations from mobile.'
            : automationErrorMessage(catalog.error),
      );
    }
    if (catalog.value == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
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
          if (attention > 0 &&
              filters.bucket != AutomationBucket.needsAttention)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
              child: AleraNotice(
                icon: AleraIcons.warning,
                message: attention == 1
                    ? '1 automation needs attention.'
                    : '$attention automations need attention.',
                action: TextButton(
                  onPressed: () => controller.setFilters(
                    mobileAutomationFilters(
                      filters,
                      bucket: () => AutomationBucket.needsAttention,
                    ),
                  ),
                  child: const Text('Show'),
                ),
              ),
            ),
          AleraSearchField(
            hintText: 'Search Automations',
            initialValue: filters.search,
            debounce: AleraTokens.durationMid,
            onChanged: (value) => controller.setFilters(
              mobileAutomationFilters(filters, search: value),
            ),
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          MobileAutomationBucketChips(
            selected: filters.bucket,
            counts: counts,
            onSelected: (bucket) => controller.setFilters(
              mobileAutomationFilters(filters, bucket: () => bucket),
            ),
          ),
          if (list.scope != AutomationScope.all)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.spaceSm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AleraChip(
                  label: _scopeLabel(list.scope, names),
                  onRemove: () => controller.setScope(AutomationScope.all),
                ),
              ),
            ),
          const SizedBox(height: AleraTokens.spaceSm),
          if (visible.isEmpty)
            filtered
                ? AleraEmptyState(
                    icon: AleraIcons.searchEmpty,
                    title: 'No Matches',
                    message: 'No automations match these filters.',
                    action: TextButton(
                      onPressed: controller.clear,
                      child: const Text('Clear Filters'),
                    ),
                  )
                : AleraEmptyState(
                    icon: AleraIcons.schedule,
                    title: 'No Automations Yet',
                    message: 'Schedule a prompt for an agent on this host.',
                    action: FilledButton.icon(
                      onPressed: () => unawaited(
                        startAutomationAuthoring(context, ref, hostId),
                      ),
                      icon: const Icon(AleraIcons.add),
                      label: const Text('New Automation'),
                    ),
                  )
          else if (workspaceId != null) ...<Widget>[
            const AleraSectionHeader(label: 'Scheduled Here'),
            ...visible.map(card),
          ] else
            for (final group in groupAutomations(
              visible,
              keyOf: (automation) => automation.effectiveProjectId,
              labelOf: names.projectName,
            )) ...<Widget>[
              AleraSectionHeader(
                label: group.label,
                trailing: AleraBadge(label: '${group.automations.length}'),
              ),
              ...group.automations.map(card),
            ],
          if (workspaceId != null)
            MobileAutomationWorkspaceRuns(
              hostId: hostId,
              workspaceId: workspaceId,
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

String _scopeLabel(AutomationScope scope, MobileAutomationContext names) =>
    switch (scope.kind) {
      AutomationScopeKind.project => 'Project: ${names.projectName(scope.id)}',
      AutomationScopeKind.section => 'Section: ${names.sectionName(scope.id)}',
      AutomationScopeKind.workspace =>
        'Workspace: ${names.workspaceName(scope.id)}',
      AutomationScopeKind.all => 'All Automations',
    };
