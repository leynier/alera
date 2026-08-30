part of 'workbench_view_options_menu.dart';

/// One pickable tag for the filter section: id plus display name.
typedef _TagOption = ({String id, String name});

class const _TagsFilterSection({
  required final List<_TagOption> selectedTags,
  required final List<_TagOption> availableTags,
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
            _SectionLabel(text: 'Tags'),
            const SizedBox(width: AleraTokens.space6),
            if (selectedTags.isNotEmpty)
              AleraBadge(label: selectedTags.length.toString()),
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
        if (selectedTags.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            children: <Widget>[
              for (final tag in selectedTags)
                AleraChip(label: tag.name, onRemove: () => onRemove(tag.id)),
            ],
          ),
        ],
        const SizedBox(height: AleraTokens.space8),
        AleraTextField(
          dense: true,
          prefixIcon: AleraIcons.add,
          hintText: 'Add tag…',
          controller: searchController,
          onSubmitted: (_) {
            if (availableTags.isNotEmpty) {
              onAdd(availableTags.first.id);
            }
          },
        ),
        const SizedBox(height: AleraTokens.space8),
        _AvailableTagsList(
          tags: availableTags,
          hasSelection: selectedTags.isNotEmpty,
          query: query,
          onPick: onAdd,
          theme: theme,
        ),
      ],
    );
  }
}

class const _AvailableTagsList({
  required final List<_TagOption> tags,
  required final bool hasSelection,
  required final String query,
  required final ValueChanged<String> onPick,
  required final ThemeData theme,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      final emptyMessage = query.isNotEmpty
          ? 'No tags match "$query"'
          : (hasSelection ? 'All tags selected' : 'No tags yet');
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
            for (final tag in tags)
              _AvailableTagRow(tag: tag, onPick: () => onPick(tag.id)),
          ],
        ),
      ),
    );
  }
}

class const _AvailableTagRow({
  required final _TagOption tag,
  required final VoidCallback onPick,
}) extends StatefulWidget {
  @override
  State<_AvailableTagRow> createState() => _AvailableTagRowState();
}

class _AvailableTagRowState extends State<_AvailableTagRow> {
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
                AleraIcons.tag,
                size: 12,
                color: AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  widget.tag.name,
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
