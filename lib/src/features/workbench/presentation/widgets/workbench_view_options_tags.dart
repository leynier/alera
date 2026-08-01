part of 'workbench_view_options_menu.dart';

/// One pickable tag for the filter section: id plus display name.
typedef _TagOption = ({String id, String name});

class _TagsFilterSection extends StatelessWidget {
  const _TagsFilterSection({
    required this.selectedTags,
    required this.availableTags,
    required this.query,
    required this.searchController,
    required this.onAdd,
    required this.onRemove,
    required this.onClear,
    required this.theme,
  });

  final List<_TagOption> selectedTags;
  final List<_TagOption> availableTags;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback? onClear;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _AvailableTagsList extends StatelessWidget {
  const _AvailableTagsList({
    required this.tags,
    required this.hasSelection,
    required this.query,
    required this.onPick,
    required this.theme,
  });

  final List<_TagOption> tags;
  final bool hasSelection;
  final String query;
  final ValueChanged<String> onPick;
  final ThemeData theme;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final tag in tags)
              _AvailableTagRow(tag: tag, onPick: () => onPick(tag.id)),
          ],
        ),
      ),
    );
  }
}

class _AvailableTagRow extends StatefulWidget {
  const _AvailableTagRow({required this.tag, required this.onPick});

  final _TagOption tag;
  final VoidCallback onPick;

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
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
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
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
