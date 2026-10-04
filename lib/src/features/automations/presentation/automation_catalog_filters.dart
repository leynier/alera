import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/domain/automation_catalog_query.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:flutter/material.dart';

/// Scope, search and named filters. Always rendered, including when nothing
/// matches, so a filter can always be cleared from where it was set.
class AutomationCatalogFiltersBar extends StatefulWidget {
  const AutomationCatalogFiltersBar({
    super.key,
    required this.scope,
    required this.filters,
    required this.counts,
    required this.automations,
    required this.context,
    required this.tags,
    required this.onScope,
    required this.onFilters,
    required this.onClear,
  });

  final AutomationScope scope;
  final AutomationCatalogFilters filters;
  final Map<AutomationBucket, int> counts;
  final List<AutomationRecord> automations;
  final AutomationWorkbenchContext context;
  final Map<String, String> tags;
  final ValueChanged<AutomationScope> onScope;
  final ValueChanged<AutomationCatalogFilters> onFilters;
  final VoidCallback onClear;

  @override
  State<AutomationCatalogFiltersBar> createState() =>
      _AutomationCatalogFiltersBarState();
}

class _AutomationCatalogFiltersBarState
    extends State<AutomationCatalogFiltersBar> {
  late final TextEditingController _search = TextEditingController(
    text: widget.filters.search,
  );
  Timer? _debounce;

  @override
  void didUpdateWidget(AutomationCatalogFiltersBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filters.search != _search.text &&
        oldWidget.filters.search != widget.filters.search) {
      _search.text = widget.filters.search;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  AutomationCatalogFilters _with({
    String? search,
    String? Function()? projectId,
    String? Function()? hostId,
    String? Function()? profileId,
    String? Function()? tagId,
    AutomationBucket? Function()? bucket,
  }) {
    final current = widget.filters;
    return AutomationCatalogFilters(
      search: search ?? current.search,
      projectId: projectId == null ? current.projectId : projectId(),
      hostId: hostId == null ? current.hostId : hostId(),
      profileId: profileId == null ? current.profileId : profileId(),
      tagId: tagId == null ? current.tagId : tagId(),
      bucket: bucket == null ? current.bucket : bucket(),
    );
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      AleraTokens.durationMid,
      () => widget.onFilters(_with(search: value)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.context;
    final scopeEntries = <AleraDropdownFieldEntry<AutomationScope>>[
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
    if (!scopeEntries.any((entry) => entry.value == widget.scope)) {
      scopeEntries.add(
        AleraDropdownFieldEntry(
          value: widget.scope,
          label: switch (widget.scope.kind) {
            AutomationScopeKind.project => 'Unavailable Project',
            AutomationScopeKind.section => 'Unavailable Section',
            _ => 'Unavailable Workspace',
          },
        ),
      );
    }
    final hostIds = <String>{
      for (final automation in widget.automations) ?automation.targetHostId,
    };
    final profileIds = <String>{
      for (final automation in widget.automations) ?automation.agentProfileId,
    };
    final tagIds = <String>{
      for (final automation in widget.automations) ...automation.tagIds,
    };
    final filters = widget.filters;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDropdownField<AutomationScope>(
            labelText: 'Scope',
            value: widget.scope,
            entries: scopeEntries,
            filterable: true,
            filterHintText: 'Search Projects, Sections And Workspaces',
            onChanged: widget.onScope,
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraSearchField(
            controller: _search,
            hintText: 'Search Automations',
            onChanged: _changed,
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<AutomationBucket?>(
            labelText: 'Status',
            value: filters.bucket,
            entries: <AleraDropdownFieldEntry<AutomationBucket?>>[
              const AleraDropdownFieldEntry(value: null, label: 'All'),
              for (final bucket in AutomationBucket.values)
                AleraDropdownFieldEntry(
                  value: bucket,
                  label: '${bucket.label} (${widget.counts[bucket] ?? 0})',
                ),
            ],
            onChanged: (value) => widget.onFilters(_with(bucket: () => value)),
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<String?>(
            labelText: 'Project',
            value: filters.projectId,
            filterable: true,
            filterHintText: 'Search Projects',
            entries: <AleraDropdownFieldEntry<String?>>[
              const AleraDropdownFieldEntry(value: null, label: 'All Projects'),
              for (final project in names.projects)
                AleraDropdownFieldEntry(value: project.id, label: project.name),
            ],
            onChanged: (value) =>
                widget.onFilters(_with(projectId: () => value)),
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraDropdownField<String?>(
            labelText: 'Host',
            value: filters.hostId,
            entries: <AleraDropdownFieldEntry<String?>>[
              const AleraDropdownFieldEntry(value: null, label: 'All Hosts'),
              for (final host in hostIds)
                AleraDropdownFieldEntry(
                  value: host,
                  label: names.hostName(host),
                ),
            ],
            onChanged: (value) => widget.onFilters(_with(hostId: () => value)),
          ),
          const SizedBox(height: AleraTokens.space8),
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
                widget.onFilters(_with(profileId: () => value)),
          ),
          if (tagIds.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            AleraDropdownField<String?>(
              labelText: 'Tag',
              value: filters.tagId,
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry(value: null, label: 'All Tags'),
                for (final tag in tagIds)
                  AleraDropdownFieldEntry(
                    value: tag,
                    label: widget.tags[tag] ?? tag,
                  ),
              ],
              onChanged: (value) => widget.onFilters(_with(tagId: () => value)),
            ),
          ],
          if (filters.isFiltered || widget.scope != AutomationScope.all)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  _debounce?.cancel();
                  _search.clear();
                  widget.onClear();
                },
                child: const Text('Clear Filters'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space8),
              child: Text(
                'Showing every automation on this runtime.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
