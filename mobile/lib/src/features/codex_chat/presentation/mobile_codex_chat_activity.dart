part of 'mobile_codex_chat_screen.dart';

class _MobileWorkingRow extends StatelessWidget {
  const _MobileWorkingRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
    child: _MobileCodexShimmerText(
      text: 'Working',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AleraTokens.foregroundMuted,
        fontFamily: AleraTokens.monoFontFamily,
      ),
    ),
  );
}

class _MobileActivityGroup extends StatelessWidget {
  const _MobileActivityGroup({
    required this.cells,
    required this.expanded,
    required this.onToggle,
  });

  final List<MobileCodexTimelineCell> cells;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final visible = cells.where((cell) => !cell.isReasoning).toList();
    final streaming = cells.any((cell) => cell.isStreaming);
    final failed = visible.any((cell) => cell.status == 'failed');
    final summary =
        '${_mobileActivitySummary(visible)}${failed ? ' · Failed' : ''}';
    final color = failed ? AleraTokens.error : AleraTokens.foregroundMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.edit_note_outlined,
                    size: AleraTokens.space16,
                    color: color,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: streaming
                        ? _MobileCodexShimmerText(
                            text: summary,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: color),
                          )
                        : Text(
                            summary,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: color),
                          ),
                  ),
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: AleraTokens.space16,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space12),
              child: Column(
                children: <Widget>[
                  for (final cell in visible) _MobileActivityItem(cell: cell),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MobileActivityItem extends StatelessWidget {
  const _MobileActivityItem({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final kind = _mobileActivityKind(cell);
    final target = kind == _MobileActivityKind.viewImage
        ? cell.subtitle ?? cell.metadata['path']?.toString()
        : cell.subtitle ?? cell.title ?? cell.displayText;
    final label = kind == _MobileActivityKind.viewImage
        ? target == null || target.isEmpty
              ? 'Viewed image'
              : 'Viewed image · $target'
        : '${_mobileActivityVerb(kind)} $target';
    final details = cell.displayText.trim();
    final showsDistinctDetails =
        details.isNotEmpty && details != target && details != cell.title;
    final color = _mobileCellColor(cell);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _mobileActivityIcon(kind),
              size: AleraTokens.space16,
              color: color,
            ),
            title: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          if (showsDistinctDetails)
            Padding(
              padding: const EdgeInsets.only(left: AleraTokens.space24),
              child: _MobileCodexMarkdown(text: details),
            ),
        ],
      ),
    );
  }
}

enum _MobileActivityKind { read, viewImage, search, list, edit, run }

_MobileActivityKind _mobileActivityKind(MobileCodexTimelineCell cell) {
  final value = '${cell.title} ${cell.subtitle} ${cell.metadata['itemType']}'
      .toLowerCase();
  if (value.contains('imageview') || value.contains('viewed image')) {
    return _MobileActivityKind.viewImage;
  }
  if (cell.kind == 'diff' ||
      value.contains('edit') ||
      value.contains('write')) {
    return _MobileActivityKind.edit;
  }
  if (value.contains('search') || value.contains('grep')) {
    return _MobileActivityKind.search;
  }
  if (value.contains('list') || value.contains('glob')) {
    return _MobileActivityKind.list;
  }
  if (value.contains('read') || value.contains('open')) {
    return _MobileActivityKind.read;
  }
  return _MobileActivityKind.run;
}

IconData _mobileActivityIcon(_MobileActivityKind kind) => switch (kind) {
  _MobileActivityKind.read => Icons.menu_book_outlined,
  _MobileActivityKind.viewImage => AleraIcons.viewImage,
  _MobileActivityKind.search => Icons.search,
  _MobileActivityKind.list => Icons.list_alt_outlined,
  _MobileActivityKind.edit => Icons.edit_outlined,
  _MobileActivityKind.run => Icons.terminal,
};

String _mobileActivityVerb(_MobileActivityKind kind) => switch (kind) {
  _MobileActivityKind.read => 'Read',
  _MobileActivityKind.viewImage => 'Viewed',
  _MobileActivityKind.search => 'Searched',
  _MobileActivityKind.list => 'Listed',
  _MobileActivityKind.edit => 'Edited',
  _MobileActivityKind.run => 'Ran',
};

String _mobileActivitySummary(List<MobileCodexTimelineCell> cells) {
  final counts = <_MobileActivityKind, int>{};
  for (final cell in cells) {
    counts.update(
      _mobileActivityKind(cell),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  return <String>[
    for (final kind in _MobileActivityKind.values)
      if ((counts[kind] ?? 0) > 0)
        '${_mobileActivityVerb(kind)} ${counts[kind]} ${_mobileActivityNoun(kind, counts[kind]!)}',
  ].join(', ');
}

String _mobileActivityNoun(_MobileActivityKind kind, int count) {
  if (kind == _MobileActivityKind.run) {
    return count == 1 ? 'command' : 'commands';
  }
  if (kind == _MobileActivityKind.viewImage) {
    return count == 1 ? 'image' : 'images';
  }
  return count == 1 ? 'file' : 'files';
}
