part of 'workspace_search_panel.dart';

@visibleForTesting
class const WorkspaceSearchTextRange({
  required final int start,
  required final int end,
});

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

class const _SearchSummary({required final WorkspaceSearchState state})
    extends StatelessWidget {
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
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
              overflow: .ellipsis,
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

class const _SearchEmptyState({required final WorkspaceSearchState state})
    extends StatelessWidget {
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
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}

class const _SearchPathParts({
  required final String name,
  required final String directory,
}) {
  factory from(String relativePath) {
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

class const _SearchFileResultRow({
  required final native.WorkspaceSearchFileResult file,
  required final bool collapsed,
  required final int depth,
  required final bool showDirectory,
  required final bool replacing,
  required final VoidCallback onToggleCollapsed,
  required final VoidCallback? onReplaceFile,
}) extends StatelessWidget {
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
              kind: .file,
              size: 15,
              fallbackColor: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space6),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: .ellipsis,
                text: TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: path.name,
                      style: textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
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
                textAlign: .right,
                style: textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w700,
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

class const _SearchDirectoryResultRow({
  required final String name,
  required final int matchCount,
  required final int depth,
  required final bool collapsed,
  required final VoidCallback onToggleCollapsed,
}) extends StatelessWidget {
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
              kind: .folder,
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
                  fontWeight: .w600,
                ),
                overflow: .ellipsis,
              ),
            ),
            SizedBox(
              width: AleraTokens.space24,
              child: Text(
                '$matchCount',
                textAlign: .right,
                style: textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: .w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _SearchMatchResultRow({
  required final native.WorkspaceSearchFileResult file,
  required final native.WorkspaceSearchMatch match,
  required final int depth,
  required final bool replacing,
  required final bool showReplacementPreview,
  required final VoidCallback onOpen,
  required final VoidCallback? onReplace,
}) extends StatelessWidget {
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
          crossAxisAlignment: .start,
          children: <Widget>[
            SizedBox(
              width: AleraTokens.space32,
              child: Text(
                '${match.line}',
                style: _searchMonoBodySmall(
                  context,
                  color: AleraTokens.foregroundFaint,
                ),
                textAlign: .right,
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
            Expanded(
              child: RichText(
                text: showReplacementPreview && preview != null
                    ? _replacementPreviewSpan(context, match, preview)
                    : _matchLineSpan(context, match),
                maxLines: 2,
                overflow: .ellipsis,
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
      fontWeight: .w700,
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
      decoration: .lineThrough,
      decorationColor: AleraTokens.error,
    );
    final newStyle = baseStyle.copyWith(
      color: AleraTokens.success,
      fontWeight: .w700,
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
