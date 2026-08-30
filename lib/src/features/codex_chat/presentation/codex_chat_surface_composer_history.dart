part of 'codex_chat_surface.dart';

extension _CodexComposerHistory on _CodexComposerState {
  bool _navigatePromptHistory(LogicalKeyboardKey key) {
    if (widget.promptHistory.isEmpty) return false;
    final value = widget.controller.value;
    if (!codexCanNavigatePromptHistory(
      key: key,
      value: value,
      browsingHistory: _historyIndex != null,
    )) {
      return false;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _historyDraft ??= value.text;
      _historyIndex = _historyIndex == null
          ? widget.promptHistory.length - 1
          : (_historyIndex! - 1).clamp(0, widget.promptHistory.length - 1);
      _applyHistoryText(widget.promptHistory[_historyIndex!]);
      return true;
    }
    if (_historyIndex == null) return false;
    if (_historyIndex! < widget.promptHistory.length - 1) {
      _historyIndex = _historyIndex! + 1;
      _applyHistoryText(widget.promptHistory[_historyIndex!]);
    } else {
      final draft = _historyDraft ?? '';
      _historyIndex = null;
      _historyDraft = null;
      _applyHistoryText(draft);
    }
    return true;
  }

  void _applyHistoryText(String text) {
    _applyingHistory = true;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: .collapsed(offset: text.length),
    );
    _applyingHistory = false;
  }
}

@visibleForTesting
bool codexCanNavigatePromptHistory({
  required LogicalKeyboardKey key,
  required TextEditingValue value,
  required bool browsingHistory,
}) {
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return false;
  final cursor = selection.baseOffset;
  if (key == LogicalKeyboardKey.arrowUp) {
    return browsingHistory
        ? cursor == value.text.length
        : value.text.isEmpty || cursor == 0;
  }
  if (key == LogicalKeyboardKey.arrowDown) {
    return browsingHistory && cursor == value.text.length;
  }
  return false;
}
