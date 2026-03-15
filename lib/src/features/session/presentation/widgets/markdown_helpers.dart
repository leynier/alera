import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:remend/remend.dart';

@visibleForTesting
bool Function() copyMouseConnectionDetector = () =>
    RendererBinding.instance.mouseTracker.mouseIsConnected;

bool mouseIsConnected() => copyMouseConnectionDetector();

Widget buildMarkdownContent({
  required BuildContext context,
  required String text,
  required bool markdownEnabled,
  required TextStyle? textStyle,
  TextStyle? markdownStyle,
  TextAlign? textAlign,
}) {
  if (!markdownEnabled) {
    return Text(
      normalizeMarkdownNewlines(text),
      style: textStyle,
      textAlign: textAlign,
    );
  }
  final prepared = remend(normalizeMarkdownNewlines(text));
  return MarkdownBody(
    data: prepared,
    styleSheet: _buildStyleSheet(markdownStyle ?? textStyle),
    selectable: true,
  );
}

MarkdownStyleSheet _buildStyleSheet(TextStyle? baseStyle) {
  final base = baseStyle ?? const TextStyle(color: AleraTokens.foreground);
  return MarkdownStyleSheet(
    p: base,
    strong: base.copyWith(fontWeight: FontWeight.bold),
    em: base.copyWith(fontStyle: FontStyle.italic),
    code: AleraTokens.monoStyle,
    codeblockDecoration: BoxDecoration(
      color: AleraTokens.surfaceVariant,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: AleraTokens.borderSubtle, width: 3),
      ),
    ),
    a: base.copyWith(color: AleraTokens.info),
    tableBorder: TableBorder.all(color: AleraTokens.border),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: AleraTokens.border),
      ),
    ),
    blockSpacing: AleraTokens.space8,
  );
}

final _blockLinePattern = RegExp(
  r'^(?:[-*] |> |#{1,6} |\d+\. |\[[ x]\] |\([ x]\) |```|---+|\|)',
);

final _listItemStart = RegExp(
  r'^(?:[-*] |\d+\. |\[[ x]\] |\([ x]\) )',
);

final _tableRowStart = RegExp(r'^\|');

/// Converts single newlines within paragraphs to spaces so that text
/// reflows to fill the available width.  Preserves paragraph breaks
/// (\n\n), newlines adjacent to block-level markdown elements, and
/// content inside fenced code blocks.
@visibleForTesting
String normalizeMarkdownNewlines(String text) {
  final codeBlockRe = RegExp(r'```.*?```', dotAll: true);
  final placeholders = <String>[];
  var work = text.replaceAllMapped(codeBlockRe, (m) {
    placeholders.add(m[0]!);
    return '\x00CB${placeholders.length - 1}\x00';
  });
  final paragraphs = work.split('\n\n');
  final processed = paragraphs.map((paragraph) {
    final lines = paragraph.split('\n');
    if (lines.length <= 1) return paragraph;
    final buf = StringBuffer(lines[0]);
    for (var i = 1; i < lines.length; i++) {
      final cur = lines[i].trimLeft();
      final prev = lines[i - 1].trimLeft();
      final isTableCur = _tableRowStart.hasMatch(cur);
      final isBlockCur = _blockLinePattern.hasMatch(cur);
      final isBlockPrev = _blockLinePattern.hasMatch(prev);
      final isListPrev = _listItemStart.hasMatch(prev);
      final isTablePrev = _tableRowStart.hasMatch(prev);
      if (isTableCur && isTablePrev &&
          !lines[i - 1].trimRight().endsWith('|')) {
        buf.write(' ');
      } else if (isBlockCur) {
        buf.write('\n');
      } else if (isBlockPrev && !isListPrev) {
        buf.write('\n');
      } else if (!lines[i - 1].endsWith(' ')) {
        buf.write(' ');
      }
      buf.write(lines[i]);
    }
    return buf.toString();
  }).where((p) => p.isNotEmpty).toList();
  final joined = StringBuffer();
  for (var i = 0; i < processed.length; i++) {
    if (i > 0) {
      final prevLast = processed[i - 1].split('\n').last.trimLeft();
      final curFirst = processed[i].split('\n').first.trimLeft();
      if ((_listItemStart.hasMatch(prevLast) &&
              _listItemStart.hasMatch(curFirst)) ||
          (_tableRowStart.hasMatch(prevLast) &&
              _tableRowStart.hasMatch(curFirst))) {
        joined.write('\n');
      } else {
        joined.write('\n\n');
      }
    }
    joined.write(processed[i]);
  }
  final normalized = joined.toString();
  var result = normalized;
  for (var i = 0; i < placeholders.length; i++) {
    result = result.replaceFirst('\x00CB$i\x00', placeholders[i]);
  }
  return result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
}

class MessageActionButtons extends StatelessWidget {
  const MessageActionButtons({
    super.key,
    required this.alignLeft,
    required this.copyKey,
    required this.copyText,
    required this.copiedLabel,
    required this.toggleKey,
    required this.markdownEnabled,
    required this.onToggleMarkdown,
    this.active = true,
  });

  final bool alignLeft;
  final ValueKey<String> copyKey;
  final String copyText;
  final String copiedLabel;
  final ValueKey<String> toggleKey;
  final bool markdownEnabled;
  final ValueChanged<bool> onToggleMarkdown;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final copy = MessageCopyButton(
      key: copyKey,
      copyText: copyText,
      copiedLabel: copiedLabel,
      active: active,
    );
    final markdownToggle = MessageMarkdownToggleButton(
      key: toggleKey,
      markdownEnabled: markdownEnabled,
      onChanged: onToggleMarkdown,
      active: active,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignLeft
          ? <Widget>[
              copy,
              const SizedBox(width: AleraTokens.space2),
              markdownToggle,
            ]
          : <Widget>[
              markdownToggle,
              const SizedBox(width: AleraTokens.space2),
              copy,
            ],
    );
  }
}

class MessageCopyButton extends StatelessWidget {
  const MessageCopyButton({
    super.key,
    required this.copyText,
    required this.copiedLabel,
    this.active = true,
  });

  final String copyText;
  final String copiedLabel;
  final bool active;

  Future<void> _copy(BuildContext context) async {
    if (copyText.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: copyText));
    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: copiedLabel,
      tone: AleraToastTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool effectivelyActive = !mouseIsConnected() || active;
    return InkWell(
      onTap: effectivelyActive ? () => _copy(context) : null,
      mouseCursor: effectivelyActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space4,
          vertical: AleraTokens.space2,
        ),
        child: Icon(
          Icons.content_copy,
          size: 12,
          color: effectivelyActive ? AleraTokens.foregroundFaint : Colors.transparent,
        ),
      ),
    );
  }
}

class MessageMarkdownToggleButton extends StatelessWidget {
  const MessageMarkdownToggleButton({
    super.key,
    required this.markdownEnabled,
    required this.onChanged,
    this.active = true,
  });

  final bool markdownEnabled;
  final ValueChanged<bool> onChanged;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final bool effectivelyActive = !mouseIsConnected() || active;
    return Tooltip(
      message: effectivelyActive ? (markdownEnabled ? 'Markdown on' : 'Markdown off') : '',
      child: InkWell(
        onTap: effectivelyActive ? () => onChanged(!markdownEnabled) : null,
        mouseCursor: effectivelyActive ? SystemMouseCursors.click : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Icon(
            Icons.code,
            size: 13,
            color: effectivelyActive ? AleraTokens.foregroundFaint : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
