part of 'workbench_view_options_menu.dart';

class const _ShowWorkspacesSettings({
  required final bool showActiveWorkspacesOnly,
  required final bool showPinnedWorkspacesBelow,
  required final bool showArchivedWorkspaces,
  required final ValueChanged<bool> onShowActiveWorkspacesOnly,
  required final ValueChanged<bool> onShowPinnedWorkspacesBelow,
  required final ValueChanged<bool> onShowArchivedWorkspaces,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingsGroup(
      title: 'Show Workspaces',
      description: 'Choose which workspaces appear in the sidebar.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Active Workspaces Only',
          description:
              'Hide workspaces that do not have an open terminal or Codex tab.',
          controlWidth: 56,
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: showActiveWorkspacesOnly,
              onChanged: onShowActiveWorkspacesOnly,
            ),
          ),
        ),
        AleraSettingRow(
          title: 'Repeat Pinned Workspaces',
          description: 'Also show pinned workspaces in their regular project or All groups.',
          controlWidth: 56,
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: showPinnedWorkspacesBelow,
              onChanged: onShowPinnedWorkspacesBelow,
            ),
          ),
        ),
        AleraSettingRow(
          title: 'Show Archived Workspaces',
          description: 'Show archived workspaces in the sidebar.',
          controlWidth: 56,
          child: Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: showArchivedWorkspaces,
              onChanged: onShowArchivedWorkspaces,
            ),
          ),
        ),
      ],
    );
  }
}

class const _SectionsFilterSection({
  required final List<WorkspaceSection> selectedSections,
  required final List<WorkspaceSection> availableSections,
  required final String query,
  required final TextEditingController searchController,
  required final ValueChanged<String> onAdd,
  required final ValueChanged<String> onRemove,
  required final VoidCallback? onClear,
  required final ThemeData theme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            _SectionLabel(text: 'Sections'),
            const SizedBox(width: AleraTokens.space6),
            if (selectedSections.isNotEmpty)
              AleraBadge(label: selectedSections.length.toString()),
            const Spacer(),
            MouseRegion(
              cursor: onClear == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: AleraTokens.foregroundMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                  ),
                  minimumSize: const Size(0, 24),
                  tapTargetSize: .shrinkWrap,
                ),
                child: Text('Clear', style: theme.textTheme.labelSmall),
              ),
            ),
          ],
        ),
        if (selectedSections.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final section in selectedSections)
                AleraChip(
                  label: section.name,
                  onRemove: () => onRemove(section.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AleraTokens.space8),
        AleraTextField(
          dense: true,
          prefixIcon: AleraIcons.add,
          hintText: 'Add section\u2026',
          controller: searchController,
          onSubmitted: (_) {
            if (availableSections.isNotEmpty) {
              onAdd(availableSections.first.id);
            }
          },
        ),
        const SizedBox(height: AleraTokens.space8),
        _AvailableSectionsList(
          sections: availableSections,
          hasSelection: selectedSections.isNotEmpty,
          query: query,
          onPick: onAdd,
          theme: theme,
        ),
      ],
    );
  }
}

class const _AvailableSectionsList({
  required final List<WorkspaceSection> sections,
  required final bool hasSelection,
  required final String query,
  required final ValueChanged<String> onPick,
  required final ThemeData theme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      final emptyMessage = query.isNotEmpty
          ? 'No sections match "$query"'
          : (hasSelection ? 'All sections selected' : 'No sections yet');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
        child: Center(
          child: Text(
            emptyMessage,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 160),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            for (final section in sections)
              _AvailableSectionRow(
                section: section,
                onPick: () => onPick(section.id),
              ),
          ],
        ),
      ),
    );
  }
}

class const _AvailableSectionRow({
  required final WorkspaceSection section,
  required final VoidCallback onPick,
}) extends StatefulWidget {
  @override
  State<_AvailableSectionRow> createState() => _AvailableSectionRowState();
}

class _AvailableSectionRowState extends State<_AvailableSectionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onPick,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: _hovered ? AleraTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                AleraIcons.section,
                size: 12,
                color: AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  widget.section.name,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
