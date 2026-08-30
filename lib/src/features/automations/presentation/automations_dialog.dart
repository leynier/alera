import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_widgets.dart';
import 'package:alera/src/features/automations/presentation/automation_editor_dialog.dart';
import 'package:alera/src/features/automations/presentation/automation_run_choice_dialogs.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

part 'automations_dialog_actions.dart';

Future<void> showAutomationsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const AutomationsDialog(),
  );
}

class AutomationsDialog extends ConsumerStatefulWidget {
  const AutomationsDialog({super.key});

  @override
  ConsumerState<AutomationsDialog> createState() => _AutomationsDialogState();
}

class _AutomationsDialogState extends ConsumerState<AutomationsDialog> {
  String? _selectedId;
  Future<AutomationDetail>? _detailFuture;
  final TextEditingController _search = TextEditingController();
  String? _stateFilter;
  String? _projectFilter;
  String? _profileFilter;
  String? _tagFilter;
  bool _includeTrashed = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final automations = ref.watch(automationCatalogProvider(_includeTrashed));
    return AleraDialog(
      maxWidth: AleraTokens.automationDialogWidth,
      maxHeight: AleraTokens.automationDialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: SizedBox(
          height: AleraTokens.automationDialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AutomationDialogHeader(
                onClose: () => Navigator.of(context).pop(),
                onImport: () => unawaited(_importCatalog()),
                onExport: () => unawaited(_exportCatalog()),
              ),
              const SizedBox(height: AleraTokens.space16),
              Expanded(
                child: automations.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => AleraEmptyState(
                    icon: AleraIcons.error,
                    title: 'Automations unavailable',
                    message: error.toString(),
                    action: FilledButton(
                      onPressed: () => ref.invalidate(automationListProvider),
                      child: const Text('Retry'),
                    ),
                  ),
                  data: (items) => _buildContent(context, items),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<AutomationRecord> items) {
    final visible = items.where(_matchesFilters).toList(growable: false);
    final selected = visible.isEmpty
        ? null
        : visible.firstWhere(
            (item) => item.id == _selectedId,
            orElse: () => visible.first,
          );
    final selectedId = selected?.id;
    if (selected != null && selected.id != _selectedId) {
      _selectedId = selected.id;
      _detailFuture = ref.read(automationRepositoryProvider).show(selected.id);
    }
    return AleraMasterDetail(
      masterTitle: 'Automations',
      masterAction: AleraIconButton(
        tooltip: 'New Automation',
        icon: AleraIcons.add,
        onPressed: () => unawaited(_createAutomation()),
      ),
      master: visible.isEmpty
          ? AleraEmptyState(
              icon: AleraIcons.checks,
              title: 'No automations',
              message: 'Create a schedule to run approved work in a runtime-owned target.',
              action: FilledButton(
                onPressed: () => unawaited(_createAutomation()),
                child: const Text('New Automation'),
              ),
            )
          : AleraPanel(
              clipBehavior: Clip.antiAlias,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(AleraTokens.space8),
                  child: Column(
                    children: <Widget>[
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          prefixIcon: Icon(AleraIcons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AleraTokens.space8),
                      Wrap(
                        spacing: AleraTokens.space8,
                        runSpacing: AleraTokens.space8,
                        children: <Widget>[
                          _filter('State', _stateFilter, <String?>[
                            null,
                            'draft',
                            'active',
                            'paused',
                            'blocked',
                            'archived',
                            'trashed',
                          ], (value) => setState(() => _stateFilter = value)),
                          _filter('Project', _projectFilter, <String?>[
                            null,
                            ...items
                                .map((item) => item.projectId)
                                .whereType<String>()
                                .toSet(),
                          ], (value) => setState(() => _projectFilter = value)),
                          _filter('Profile', _profileFilter, <String?>[
                            null,
                            ...items
                                .map(_profileId)
                                .whereType<String>()
                                .toSet(),
                          ], (value) => setState(() => _profileFilter = value)),
                          _filter('Tag', _tagFilter, <String?>[
                            null,
                            ...items.expand((item) => item.tagIds).toSet(),
                          ], (value) => setState(() => _tagFilter = value)),
                          FilterChip(
                            label: const Text('Trash'),
                            selected: _includeTrashed,
                            onSelected: (value) =>
                                setState(() => _includeTrashed = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                for (final automation in visible)
                  AutomationListRow(
                    automation: automation,
                    selected: automation.id == selectedId,
                    onTap: () => _select(automation.id),
                  ),
              ],
            ),
      detail: selected == null
          ? const AleraEmptyState(
              icon: AleraIcons.checks,
              title: 'Select an automation',
              message: 'Choose an automation to inspect its schedule, target, and runs.',
            )
          : AutomationDetailPane(
              future: _detailFuture ??= ref
                  .read(automationRepositoryProvider)
                  .show(selected.id),
              onRefresh: () => _refresh(selected.id),
              onEdit: () => unawaited(_edit(selected)),
              onApprove: selected.isApproved
                  ? null
                  : () => unawaited(_approve(selected)),
              onRunNow: () => unawaited(_runNow(selected)),
              onCancel: (run) => unawaited(_cancelRun(run, selected.id)),
              onResumeWaiting: (run) =>
                  unawaited(_resumeWaiting(run, selected.id)),
              onExtendWaiting: (run) =>
                  unawaited(_extendWaiting(run, selected.id)),
              onPause: selected.state == 'active'
                  ? () => unawaited(_setState('automation.pause', selected.id))
                  : null,
              onResume: selected.state == 'paused'
                  ? () => unawaited(_setState('automation.resume', selected.id))
                  : null,
              onTrash: selected.state == 'trashed'
                  ? null
                  : () => unawaited(_setState('automation.trash', selected.id)),
              onRestore: selected.state == 'trashed'
                  ? () =>
                        unawaited(_setState('automation.restore', selected.id))
                  : null,
              onClone: () => unawaited(_clone(selected)),
            ),
    );
  }

  bool _matchesFilters(AutomationRecord item) {
    final query = _search.text.trim().toLowerCase();
    final profile = _profileId(item);
    return (_stateFilter == null || item.state == _stateFilter) &&
        (_projectFilter == null || item.projectId == _projectFilter) &&
        (_profileFilter == null || profile == _profileFilter) &&
        (_tagFilter == null || item.tagIds.contains(_tagFilter)) &&
        (query.isEmpty ||
            item.name.toLowerCase().contains(query) ||
            item.slug.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query));
  }

  String? _profileId(AutomationRecord item) {
    final target = item.target;
    for (final value in target.values) {
      if (value is Map && value['agentProfileId'] is String) {
        return value['agentProfileId'] as String;
      }
    }
    return null;
  }

  Widget _filter(
    String label,
    String? value,
    List<String?> values,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButton<String?>(
      value: values.contains(value) ? value : null,
      hint: Text(label),
      items: <DropdownMenuItem<String?>>[
        for (final option in values.toSet())
          DropdownMenuItem<String?>(
            value: option,
            child: Text(option ?? 'All $label'),
          ),
      ],
      onChanged: onChanged,
    );
  }

  void _select(String id) {
    setState(() {
      _selectedId = id;
      _detailFuture = ref.read(automationRepositoryProvider).show(id);
    });
  }
}
