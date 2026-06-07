part of 'workspace_editor_surface.dart';

extension _WorkspaceEditorReveal on _WorkspaceEditorSurfaceState {
  void _reloadFromDiskAfterExternalChange() {
    if (_isDirty()) {
      return;
    }
    _document.clearSnapshot();
    unawaited(_load());
  }

  void _revealOrDefer(WorkspaceEditorRevealTarget target) {
    if (_loading || _loadError != null) {
      _document.pendingReveal = target;
      return;
    }
    _reveal(target);
  }

  void _applyPendingReveal() {
    final target = _editorSessions.takePendingReveal(widget.tab.id);
    if (target != null) {
      _revealOrDefer(target);
    }
  }

  void _reveal(WorkspaceEditorRevealTarget target) {
    if (!mounted || _controller.lineCount == 0) {
      return;
    }
    final lineIndex = (target.line - 1)
        .clamp(0, _controller.lineCount - 1)
        .toInt();
    final lineText = _controller.getLineText(lineIndex);
    final displayRange = workspaceEditorDisplayRevealRange(
      rawText: _document.loadedRawText,
      lineNumber: target.line,
      rawColumn: target.column,
      rawMatchLength: target.matchLength,
      tabSize: _currentEditorTabSize(),
    );
    final columnIndex = displayRange.columnIndex.clamp(0, lineText.length);
    final startOffset = _controller.getLineStartOffset(lineIndex) + columnIndex;
    final endOffset = (startOffset + displayRange.matchLength)
        .clamp(startOffset, _controller.length)
        .toInt();
    _controller.selection = TextSelection(
      baseOffset: startOffset,
      extentOffset: endOffset,
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _controller.scrollToLine(lineIndex);
      } on StateError {
        _document.pendingReveal = target;
      }
      _focusNode.requestFocus();
    });
  }
}

@visibleForTesting
WorkspaceEditorDisplayRevealRange workspaceEditorDisplayRevealRange({
  required String? rawText,
  required int lineNumber,
  required int rawColumn,
  required int rawMatchLength,
  required int tabSize,
}) {
  final rawLine = _rawLineAt(rawText, lineNumber);
  if (rawLine == null) {
    return WorkspaceEditorDisplayRevealRange(
      columnIndex: (rawColumn - 1).clamp(0, rawColumn).toInt(),
      matchLength: rawMatchLength,
    );
  }
  final startOffset = _displayUtf16OffsetForRawColumn(
    rawLine: rawLine,
    rawColumn: rawColumn,
    tabSize: tabSize,
  );
  final endOffset = _displayUtf16OffsetForRawColumn(
    rawLine: rawLine,
    rawColumn: rawColumn + rawMatchLength,
    tabSize: tabSize,
  );
  return WorkspaceEditorDisplayRevealRange(
    columnIndex: startOffset,
    matchLength: (endOffset - startOffset).clamp(0, endOffset).toInt(),
  );
}

@visibleForTesting
class WorkspaceEditorDisplayRevealRange {
  const WorkspaceEditorDisplayRevealRange({
    required this.columnIndex,
    required this.matchLength,
  });

  final int columnIndex;
  final int matchLength;
}

String? _rawLineAt(String? rawText, int lineNumber) {
  if (rawText == null || lineNumber < 1) {
    return null;
  }
  var currentLine = 1;
  var start = 0;
  for (var index = 0; index <= rawText.length; index += 1) {
    if (index < rawText.length && rawText.codeUnitAt(index) != 0x0A) {
      continue;
    }
    if (currentLine == lineNumber) {
      var end = index;
      if (end > start && rawText.codeUnitAt(end - 1) == 0x0D) {
        end -= 1;
      }
      return rawText.substring(start, end);
    }
    currentLine += 1;
    start = index + 1;
  }
  return null;
}

int _displayUtf16OffsetForRawColumn({
  required String rawLine,
  required int rawColumn,
  required int tabSize,
}) {
  final effectiveTabSize = tabSize.clamp(1, 8).toInt();
  final rawLength = rawLine.runes.length;
  final rawIndexLimit = (rawColumn - 1).clamp(0, rawLength).toInt();
  var rawIndex = 0;
  var visualColumn = 0;
  var utf16Offset = 0;
  for (final rune in rawLine.runes) {
    if (rawIndex >= rawIndexLimit) {
      break;
    }
    rawIndex += 1;
    if (rune == 0x09) {
      final spaces = effectiveTabSize - (visualColumn % effectiveTabSize);
      visualColumn += spaces;
      utf16Offset += spaces;
    } else {
      visualColumn += 1;
      utf16Offset += String.fromCharCode(rune).length;
    }
  }
  return utf16Offset;
}

class _EditorMessage extends StatelessWidget {
  const _EditorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
