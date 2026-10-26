import 'package:flutter/services.dart';

/// What the token at the caret asks the composer menu for.
enum AgentChatComposerTriggerKind {
  /// `@query` at a word boundary: workspace files to attach.
  mention,

  /// `/query` as the first characters of the prompt: local commands.
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

/// The trigger at the caret of [value], or `null` when the caret is not in an
/// `@` token or a leading `/` token, or when there is a selection.
///
/// A `/` only counts as the very first character of the prompt, so a path
/// such as `src/main.dart` or a slash later in a sentence never opens the
/// command menu. An `@` counts at the start of a word only, so an email
/// address does not open the file menu.
AgentChatComposerTrigger? detectAgentChatComposerTrigger(
  TextEditingValue value,
) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid || !selection.isCollapsed) return null;
  final caret = selection.extentOffset;
  if (caret < 0 || caret > text.length) return null;
  var start = caret;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  if (start == caret) return null;
  var end = caret;
  while (end < text.length && !_isSpace(text.codeUnitAt(end))) {
    end++;
  }
  final lead = text[start];
  final kind = switch (lead) {
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

/// [value] with [trigger]'s token replaced by [replacement] and the caret
/// after it. Removing a token (an empty [replacement]) also drops one space
/// after it when a space or the start of the prompt precedes it, so the
/// prompt does not keep a double space.
TextEditingValue replaceAgentChatComposerTrigger(
  TextEditingValue value,
  AgentChatComposerTrigger trigger, {
  String replacement = '',
}) {
  final text = value.text;
  final start = trigger.start.clamp(0, text.length);
  var end = trigger.end.clamp(start, text.length);
  if (replacement.isEmpty &&
      end < text.length &&
      text.codeUnitAt(end) == 0x20 &&
      (start == 0 || _isSpace(text.codeUnitAt(start - 1)))) {
    end++;
  }
  return TextEditingValue(
    text: text.replaceRange(start, end, replacement),
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}
