part of 'workspace_search_panel.dart';

@visibleForTesting
class WorkspaceSearchTextRange {
  const WorkspaceSearchTextRange({required this.start, required this.end});

  final int start;
  final int end;
}

@visibleForTesting
WorkspaceSearchTextRange workspaceSearchTextRangeForCharRange({
  required String text,
  required int oneBasedColumn,
  required int charLength,
}) {
  final startColumn = oneBasedColumn - 1;
  final start = _utf16OffsetForCharOffset(text, startColumn);
  final end = _utf16OffsetForCharOffset(text, startColumn + charLength);
  return WorkspaceSearchTextRange(start: start, end: end);
}

WorkspaceSearchTextRange _matchPreviewRange(native.WorkspaceSearchMatch match) {
  return workspaceSearchTextRangeForCharRange(
    text: match.lineContent,
    oneBasedColumn: match.displayColumn ?? match.column,
    charLength: match.displayMatchLength ?? match.matchLength,
  );
}

int _utf16OffsetForCharOffset(String text, int charOffset) {
  var remaining = charOffset < 0 ? 0 : charOffset;
  var utf16Offset = 0;
  while (utf16Offset < text.length && remaining > 0) {
    final codeUnit = text.codeUnitAt(utf16Offset);
    final nextOffset =
        _isLeadingSurrogate(codeUnit) &&
            utf16Offset + 1 < text.length &&
            _isTrailingSurrogate(text.codeUnitAt(utf16Offset + 1))
        ? utf16Offset + 2
        : utf16Offset + 1;
    utf16Offset = nextOffset;
    remaining -= 1;
  }
  return utf16Offset.clamp(0, text.length).toInt();
}

bool _isLeadingSurrogate(int codeUnit) {
  return codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
}

bool _isTrailingSurrogate(int codeUnit) {
  return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
}

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.state});

  final WorkspaceSearchState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    if (!state.hasQuery && !state.loading && result == null) {
      return const SizedBox.shrink();
    }
    final text = !state.hasQuery
        ? ''
        : state.loading
        ? 'Searching...'
        : result == null
        ? 'No results'
        : _resultSummary(result);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.replacing)
            const SizedBox.square(
              dimension: AleraTokens.space16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  String _resultSummary(native.WorkspaceSearchResult result) {
    final suffix = result.truncated ? ' shown' : '';
    final matchWord = result.totalMatches == 1 ? 'match' : 'matches';
    final fileWord = result.files.length == 1 ? 'file' : 'files';
    return '${result.totalMatches} $matchWord in ${result.files.length} $fileWord$suffix';
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.state});

  final WorkspaceSearchState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasQuery) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Text(
        'No results',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}

class _SearchPathParts {
  const _SearchPathParts({required this.name, required this.directory});

  final String name;
  final String directory;

  factory _SearchPathParts.from(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final directory = _searchPathContext.dirname(normalized);
    return _SearchPathParts(
      name: _searchPathContext.basename(normalized),
      directory: directory == '.' ? '' : directory,
    );
  }
}

double _searchRowLeftPadding(int depth) {
  return AleraTokens.space8 + depth * AleraTokens.space16;
}

class _SearchFileResultRow extends StatelessWidget {
  const _SearchFileResultRow({
    required this.file,
    required this.collapsed,
    required this.depth,
    required this.showDirectory,
    required this.replacing,
    required this.onToggleCollapsed,
    required this.onReplaceFile,
  });

  final native.WorkspaceSearchFileResult file;
  final bool collapsed;
  final int depth;
  final bool showDirectory;
  final bool replacing;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onReplaceFile;

  @override
  Widget build(BuildContext context) {
    final path = _SearchPathParts.from(file.relativePath);
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onToggleCollapsed,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _searchRowLeftPadding(depth),
          AleraTokens.space6,
          AleraTokens.space8,
          AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraFileIcon(
              pathOrName: path.name,
              kind: AleraFileIconKind.file,
              size: 15,
              fallbackColor: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space6),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: path.name,
                      style: textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showDirectory && path.directory.isNotEmpty)
                      TextSpan(
                        text: '  ${path.directory}',
                        style: textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: AleraTokens.space24,
              child: Text(
                '${file.matches.length}',
                textAlign: TextAlign.right,
                style: textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Replace in file',
              icon: AleraIcons.findReplace,
              onPressed: replacing ? null : onReplaceFile,
              minSize: AleraTokens.space24,
              iconSize: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchDirectoryResultRow extends StatelessWidget {
  const _SearchDirectoryResultRow({
    required this.name,
    required this.matchCount,
    required this.depth,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final String name;
  final int matchCount;
  final int depth;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onToggleCollapsed,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _searchRowLeftPadding(depth),
          AleraTokens.space6,
          AleraTokens.space8,
          AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraFileIcon(
              pathOrName: name,
              kind: AleraFileIconKind.folder,
              isExpanded: !collapsed,
              size: 15,
              fallbackColor: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space6),
            Expanded(
              child: Text(
                name,
                style: textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: AleraTokens.space24,
              child: Text(
                '$matchCount',
                textAlign: TextAlign.right,
                style: textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMatchResultRow extends StatelessWidget {
  const _SearchMatchResultRow({
    required this.file,
    required this.match,
    required this.depth,
    required this.replacing,
    required this.showReplacementPreview,
    required this.onOpen,
    required this.onReplace,
  });

  final native.WorkspaceSearchFileResult file;
  final native.WorkspaceSearchMatch match;
  final int depth;
  final bool replacing;
  final bool showReplacementPreview;
  final VoidCallback onOpen;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final preview = match.replacementPreview;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _searchRowLeftPadding(depth),
          AleraTokens.space4,
          AleraTokens.space8,
          AleraTokens.space6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AleraTokens.space32,
              child: Text(
                '${match.line}',
                style: _searchMonoBodySmall(
                  context,
                  color: AleraTokens.foregroundFaint,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
            Expanded(
              child: RichText(
                text: showReplacementPreview && preview != null
                    ? _replacementPreviewSpan(context, match, preview)
                    : _matchLineSpan(context, match),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Replace match',
              icon: AleraIcons.findReplace,
              onPressed: replacing ? null : onReplace,
              minSize: AleraTokens.space24,
              iconSize: 14,
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _matchLineSpan(
    BuildContext context,
    native.WorkspaceSearchMatch match,
  ) {
    final baseStyle = _searchMonoBodySmall(
      context,
      color: AleraTokens.foregroundMuted,
    );
    final matchStyle = baseStyle.copyWith(
      color: AleraTokens.foreground,
      backgroundColor: AleraTokens.accentSubtle,
      fontWeight: FontWeight.w700,
    );
    final range = _clampedTextRange(
      match.lineContent.trimRight(),
      _matchPreviewRange(match),
    );
    return _lineSpanWithRange(
      text: match.lineContent.trimRight(),
      range: range,
      baseStyle: baseStyle,
      rangeStyle: matchStyle,
    );
  }

  TextSpan _replacementPreviewSpan(
    BuildContext context,
    native.WorkspaceSearchMatch match,
    String replacement,
  ) {
    final text = match.lineContent.trimRight();
    final range = _clampedTextRange(text, _matchPreviewRange(match));
    final baseStyle = _searchMonoBodySmall(
      context,
      color: AleraTokens.foregroundMuted,
    );
    final oldStyle = baseStyle.copyWith(
      color: AleraTokens.error,
      backgroundColor: AleraTokens.onError,
      decoration: TextDecoration.lineThrough,
      decorationColor: AleraTokens.error,
    );
    final newStyle = baseStyle.copyWith(
      color: AleraTokens.success,
      fontWeight: FontWeight.w700,
    );
    return TextSpan(
      children: <InlineSpan>[
        TextSpan(text: text.substring(0, range.start), style: baseStyle),
        TextSpan(text: text.substring(range.start, range.end), style: oldStyle),
        TextSpan(text: replacement, style: newStyle),
        TextSpan(text: text.substring(range.end), style: baseStyle),
      ],
    );
  }

  TextSpan _lineSpanWithRange({
    required String text,
    required WorkspaceSearchTextRange range,
    required TextStyle? baseStyle,
    required TextStyle? rangeStyle,
  }) {
    return TextSpan(
      children: <InlineSpan>[
        TextSpan(text: text.substring(0, range.start), style: baseStyle),
        TextSpan(
          text: text.substring(range.start, range.end),
          style: rangeStyle,
        ),
        TextSpan(text: text.substring(range.end), style: baseStyle),
      ],
    );
  }

  WorkspaceSearchTextRange _clampedTextRange(
    String text,
    WorkspaceSearchTextRange range,
  ) {
    final start = range.start.clamp(0, text.length).toInt();
    final end = range.end.clamp(start, text.length).toInt();
    return WorkspaceSearchTextRange(start: start, end: end);
  }
}

TextStyle _searchMonoBodySmall(BuildContext context, {required Color color}) {
  return (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
      .merge(AleraTokens.monoStyle)
      .copyWith(color: color);
}
