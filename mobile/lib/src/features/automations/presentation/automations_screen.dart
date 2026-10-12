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

/// The automations of one host, grouped by project. Opening it from a
/// workspace scopes it to that workspace; [startAuthoring] opens the
/// composer seeded from it.
class const AutomationsScreen({
  super.key,
  required final String hostId,
  final AutomationScope? initialScope,
  final String? initialAutomationId,
  final String? initialRunId,
  final bool startAuthoring = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(
        mobileAutomationListControllerProvider(widget.hostId).notifier,
      );
      if (widget.initialScope case final scope?) controller.setScope(scope);
      if (widget.initialAutomationId case final id?) {
        unawaited(_openDetail(id, runId: widget.initialRunId));
      } else if (widget.startAuthoring) {
        unawaited(_create());
      }
    });
  }

  Future<void> _openDetail(String id, {String? runId}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AutomationDetailScreen(
            hostId: widget.hostId,
            automationId: id,
            initialRunId: runId,
          ),
        ),
      );

  /// Saving stays on this list: the new automation shows up here.
  Future<void> _create() async {
    final scope = ref
        .read(mobileAutomationListControllerProvider(widget.hostId))
        .scope;
    await showMobileAutomationComposer(
      context,
      hostId: widget.hostId,
      originWorkspaceId: scope.kind == AutomationScopeKind.workspace
          ? scope.id
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(mobileAutomationCatalogProvider(widget.hostId));
    final list = ref.watch(
      mobileAutomationListControllerProvider(widget.hostId),
    );
    final controller = ref.read(
      mobileAutomationListControllerProvider(widget.hostId).notifier,
    );
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
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
      onOpen: () => unawaited(_openDetail(automation.id)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Filters',
            icon: const Icon(AleraIcons.filter),
            onPressed: () => unawaited(
              showMobileAutomationFilters(
                context,
                hostId: widget.hostId,
                automations: automations,
                names: names,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: catalog.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => unawaited(_create()),
              icon: const Icon(AleraIcons.add),
              label: const Text('New Automation'),
            ),
      body: SafeArea(
        child: catalog.value == null && catalog.hasError
            ? AleraEmptyState(
                icon: AleraIcons.loadFailed,
                title: 'Automations Unavailable',
                message: catalog.error is UnsupportedError
                    ? 'Update the runtime to manage automations from mobile.'
                    : automationErrorMessage(catalog.error),
              )
            : catalog.value == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => ref.refresh(
                  mobileAutomationCatalogProvider(widget.hostId).future,
                ),
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
                        padding: const EdgeInsets.only(
                          bottom: AleraTokens.spaceSm,
                        ),
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
                        padding: const EdgeInsets.only(
                          top: AleraTokens.spaceSm,
                        ),
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
                                onPressed: () => unawaited(_create()),
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
                          trailing: AleraBadge(
                            label: '${group.automations.length}',
                          ),
                        ),
                        ...group.automations.map(card),
                      ],
                    if (workspaceId != null)
                      MobileAutomationWorkspaceRuns(
                        hostId: widget.hostId,
                        workspaceId: workspaceId,
                        automations: automations,
                        onOpen: (run) => unawaited(
                          _openDetail(run.automationId, runId: run.id),
                        ),
                      ),
                    const SizedBox(height: AleraTokens.spaceXxl * 2),
                  ],
                ),
              ),
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
