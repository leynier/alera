/// What the token at the caret asks the composer menu for.
enum AgentChatComposerTriggerKind {
  /// `@query` at a word boundary: workspace files to attach.
  mention,

  /// `/query` as the first characters of the prompt: commands.
  command,
}

/// The token at the caret that opens the composer menu. [start] and [end]
/// span the whole token, the `@` or `/` included, so picking replaces it even
/// when the caret sits inside it.
final class const AgentChatComposerTrigger({
  required final AgentChatComposerTriggerKind kind,
  required final String query,
  required final int start,
  required final int end,
}) {
  @override
  bool operator ==(Object other) =>
      other is AgentChatComposerTrigger &&
      other.kind == kind &&
      other.query == query &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, query, start, end);

  @override
  String toString() => 'AgentChatComposerTrigger($kind, "$query", $start-$end)';
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D;

/// The trigger at the caret of [text], or `null` when the caret is not in an
/// `@` token or a leading `/` token, or when the selection is not collapsed
/// ([selectionStart] differs from [selectionEnd]).
///
/// A `/` only counts as the very first character of the prompt, so a path
/// such as `src/main.dart` or a slash later in a sentence never opens the
/// command menu, and agents only expand their commands there anyway. An `@`
/// counts at the start of a word only, so an email address does not open
/// the file menu.
AgentChatComposerTrigger? agentChatComposerTriggerAt(
  String text, {
  required int selectionStart,
  required int selectionEnd,
}) {
  if (selectionStart < 0 || selectionStart != selectionEnd) return null;
  final caret = selectionEnd;
  if (caret > text.length) return null;
  var start = caret;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  if (start == caret) return null;
  var end = caret;
  while (end < text.length && !_isSpace(text.codeUnitAt(end))) {
    end++;
  }
  final kind = switch (text[start]) {
    '@' => AgentChatComposerTriggerKind.mention,
    '/' when start == 0 => AgentChatComposerTriggerKind.command,
    _ => null,
  };
  if (kind == null) return null;
  return AgentChatComposerTrigger(
    kind: kind,
    query: text.substring(start + 1, caret),
    start: start,
    end: end,
  );
}

/// [text] with [trigger]'s token replaced by [replacement], and the caret
/// after it. Removing a token (an empty [replacement]) also drops one space
/// after it when a space or the start of the prompt precedes it, and a
/// [replacement] that ends in a space absorbs the space already there, so
/// the prompt never keeps a double space.
({String text, int caret}) agentChatComposerTriggerReplaced(
  String text,
  AgentChatComposerTrigger trigger, {
  String replacement = '',
}) {
  final start = trigger.start.clamp(0, text.length);
  var end = trigger.end.clamp(start, text.length);
  final followedBySpace = end < text.length && text.codeUnitAt(end) == 0x20;
  if (followedBySpace &&
      (replacement.isEmpty
          ? start == 0 || _isSpace(text.codeUnitAt(start - 1))
          : replacement.endsWith(' '))) {
    end++;
  }
  return (
    text: text.replaceRange(start, end, replacement),
    caret: start + replacement.length,
  );
}
