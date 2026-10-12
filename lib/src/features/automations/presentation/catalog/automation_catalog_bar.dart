import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/automation_popover_chip.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<AutomationBucket?> _buckets = <AutomationBucket?>[
  null,
  .active,
  .paused,
  .drafts,
  .needsAttention,
  .completed,
  .trash,
];

/// One horizontal row of catalog filters: status buckets, Project, Agent
/// Profile and (with more than one) Host, the scope the page was opened
/// with, and a search. Always shown, so a filter can be cleared from where
/// it was set even when nothing matches.
class AutomationCatalogBar extends ConsumerStatefulWidget {
  const AutomationCatalogBar({
    super.key,
    required this.automations,
    required this.location,
    required this.names,
  });

  final List<AutomationRecord> automations;
  final AutomationsLocation location;
  final AutomationWorkbenchContext names;

  @override
  ConsumerState<AutomationCatalogBar> createState() =>
      _AutomationCatalogBarState();
}

class _AutomationCatalogBarState extends ConsumerState<AutomationCatalogBar> {
  late final TextEditingController _search = TextEditingController(
    text: widget.location.filters.search,
  );

  @override
  void didUpdateWidget(AutomationCatalogBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final search = widget.location.filters.search;
    if (search != oldWidget.location.filters.search && search != _search.text) {
      _search.text = search;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AutomationsNavigation get _navigation =>
      ref.read(automationsNavigationProvider.notifier);

  AutomationCatalogFilters _with({
    String? search,
    String? Function()? projectId,
    String? Function()? hostId,
    String? Function()? profileId,
    AutomationBucket? Function()? bucket,
  }) {
    final current = widget.location.filters;
    return AutomationCatalogFilters(
      search: search ?? current.search,
      projectId: projectId == null ? current.projectId : projectId(),
      hostId: hostId == null ? current.hostId : hostId(),
      profileId: profileId == null ? current.profileId : profileId(),
      bucket: bucket == null ? current.bucket : bucket(),
    );
  }

  Widget _filter({
    required String label,
    required String? value,
    required Map<String, String> choices,
    required ValueChanged<String?> onChanged,
  }) => AutomationPopoverChip(
    label: label,
    value: value == null ? 'All' : choices[value] ?? value,
    onClear: value == null ? null : () => onChanged(null),
    width: AleraTokens.contextMenuWidth,
    builder: (context, close) => SingleChildScrollView(
      padding: const EdgeInsets.all(AleraTokens.space4),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          for (final MapEntry(:key, value: name) in choices.entries)
            AleraMenuItem(
              label: name,
              selected: key == value,
              onTap: () {
                onChanged(key);
                close();
              },
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final filters = location.filters;
    final names = widget.names;
    final counts = automationBucketCounts(widget.automations, location.scope);
    final hosts = <String>{
      for (final automation in widget.automations) ?automation.targetHostId,
    };
    final profiles = <String>{
      for (final automation in widget.automations) ?automation.agentProfileId,
    };
    final scope = location.scope;
    final scoped = scope != AutomationScope.all;
    return AleraHorizontalScrollView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          AleraSegmentedButton<AutomationBucket?>(
            dense: true,
            selected: filters.bucket,
            segments: <ButtonSegment<AutomationBucket?>>[
              for (final bucket in _buckets)
                ButtonSegment<AutomationBucket?>(
                  value: bucket,
                  label: Text(switch (bucket) {
                    null => 'All',
                    AutomationBucket.needsAttention =>
                      '${bucket.label} (${counts[bucket] ?? 0})',
                    _ => bucket.label,
                  }),
                ),
            ],
            onSelectionChanged: (bucket) =>
                _navigation.setFilters(_with(bucket: () => bucket)),
          ),
          const SizedBox(width: AleraTokens.space8),
          _filter(
            label: 'Project',
            value: filters.projectId,
            choices: <String, String>{
              for (final project in names.projects) project.id: project.name,
            },
            onChanged: (id) =>
                _navigation.setFilters(_with(projectId: () => id)),
          ),
          const SizedBox(width: AleraTokens.space6),
          _filter(
            label: 'Agent Profile',
            value: filters.profileId,
            choices: <String, String>{
              for (final id in profiles) id: names.profileName(id),
            },
            onChanged: (id) =>
                _navigation.setFilters(_with(profileId: () => id)),
          ),
          if (hosts.length > 1 || filters.hostId != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space6),
            _filter(
              label: 'Host',
              value: filters.hostId,
              choices: <String, String>{
                for (final id in hosts) id: names.hostName(id),
              },
              onChanged: (id) =>
                  _navigation.setFilters(_with(hostId: () => id)),
            ),
          ],
          if (scoped) ...<Widget>[
            const SizedBox(width: AleraTokens.space6),
            AleraChip(
              label: switch (scope.kind) {
                AutomationScopeKind.project =>
                  'Project: ${names.projectName(scope.id)}',
                AutomationScopeKind.section =>
                  'Section: ${names.sectionName(scope.id)}',
                AutomationScopeKind.workspace =>
                  'Workspace: ${names.workspaceName(scope.id)}',
                AutomationScopeKind.all => 'All Automations',
              },
              leading: AleraIcons.section,
              tooltip: 'Show Every Automation',
              onRemove: () => _navigation.setScope(AutomationScope.all),
            ),
          ],
          const SizedBox(width: AleraTokens.space8),
          SizedBox(
            width: AleraTokens.contextMenuWidth,
            child: AleraSearchField(
              controller: _search,
              hintText: 'Search Automations',
              dense: true,
              debounce: AleraTokens.durationMid,
              onChanged: (value) =>
                  _navigation.setFilters(_with(search: value)),
            ),
          ),
          if (filters.isFiltered || scoped) ...<Widget>[
            const SizedBox(width: AleraTokens.space6),
            TextButton(
              onPressed: () {
                _search.clear();
                _navigation
                  ..clearFilters()
                  ..setScope(AutomationScope.all);
              },
              child: const Text('Clear Filters'),
            ),
          ],
        ],
      ),
    );
  }
}
