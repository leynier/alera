final RegExp _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Rewrites `$$…$$` and `$…$` math into the `\[…\]` and `\(…\)` forms the
/// Markdown renderer typesets offline, leaving fenced and inline code alone.
/// A single `$` only opens math when text follows it directly, and only
/// closes it after text that is not followed by a letter or digit, so prices
/// ("$5 and $10") and shell variables ("$HOME/$USER") stay as they are.
String agentChatDollarMath(String markdown) {
  if (!markdown.contains(r'$')) return markdown;
  final out = StringBuffer();
  final prose = StringBuffer();
  String? fence;
  final lines = markdown.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    final line = index < lines.length - 1 ? '${lines[index]}\n' : lines[index];
    final current = fence;
    if (current == null) {
      final open = _fenceOpen.firstMatch(lines[index]);
      if (open == null) {
        prose.write(line);
        continue;
      }
      out.write(_proseMath(prose.toString()));
      prose.clear();
      fence = open[1];
      out.write(line);
      continue;
    }
    out.write(line);
    final trimmed = lines[index].trim();
    if (trimmed.startsWith(current) &&
        trimmed.replaceAll(current[0], '').isEmpty) {
      fence = null;
    }
  }
  out.write(_proseMath(prose.toString()));
  return out.toString();
}

String _proseMath(String text) {
  if (!text.contains(r'$')) return text;
  final out = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length) {
      out.write(text.substring(index, index + 2));
      index += 2;
      continue;
    }
    if (char == '`') {
      final end = _codeSpanEnd(text, index);
      out.write(text.substring(index, end));
      index = end;
      continue;
    }
    if (char == r'$') {
      final display = text.startsWith(r'$$', index);
      final math = display
          ? _displayMath(text, index)
          : _inlineMath(text, index);
      if (math != null) {
        out.write(display ? '\\[${math.tex}\\]' : '\\(${math.tex}\\)');
        index = math.end;
        continue;
      }
      if (display) {
        out.write(r'$$');
        index += 2;
        continue;
      }
    }
    out.write(char);
    index += 1;
  }
  return out.toString();
}

/// The end of the code span opening at [start], or just past its backticks
/// when it never closes.
int _codeSpanEnd(String text, int start) {
  var run = start;
  while (run < text.length && text[run] == '`') {
    run += 1;
  }
  final ticks = text.substring(start, run);
  var search = run;
  while (true) {
    final close = text.indexOf(ticks, search);
    if (close < 0) return run;
    final after = close + ticks.length;
    if (after >= text.length || text[after] != '`') return after;
    search = after;
  }
}

({String tex, int end})? _displayMath(String text, int start) {
  final close = text.indexOf(r'$$', start + 2);
  if (close < 0) return null;
  final tex = text.substring(start + 2, close);
  if (tex.trim().isEmpty) return null;
  return (tex: tex, end: close + 2);
}

({String tex, int end})? _inlineMath(String text, int start) {
  final first = start + 1;
  if (first >= text.length || _isSpace(text[first])) return null;
  for (var index = first; index < text.length; index += 1) {
    final char = text[index];
    if (char == '\n') return null;
    if (char == r'\') {
      index += 1;
      continue;
    }
    if (char != r'$') continue;
    final after = index + 1 < text.length ? text[index + 1] : '';
    if (_isSpace(text[index - 1]) || _isWordCharacter(after)) return null;
    return (tex: text.substring(first, index), end: index + 1);
  }
  return null;
}

bool _isSpace(String char) => char.trim().isEmpty;

bool _isWordCharacter(String char) =>
    char.isNotEmpty && RegExp(r'[A-Za-z0-9_$]').hasMatch(char);
