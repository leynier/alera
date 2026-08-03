part of 'mobile_codex_chat_screen.dart';

/// A small native Markdown surface for the mobile package. The host already
/// prepares streaming-safe Markdown, while this widget keeps selection,
/// fenced code and tables usable without falling back to a plain text card.
class _MobileCodexMarkdown extends StatelessWidget {
  const _MobileCodexMarkdown({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    final lines = text.split('\n');
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (line.trimLeft().startsWith('```')) {
        final code = <String>[];
        index += 1;
        while (index < lines.length &&
            !lines[index].trimLeft().startsWith('```')) {
          code.add(lines[index]);
          index += 1;
        }
        if (index < lines.length) index += 1;
        blocks.add(_MobileCodeBlock(text: code.join('\n')));
        continue;
      }
      if (_isTableLine(line) &&
          index + 1 < lines.length &&
          _isTableDivider(lines[index + 1])) {
        final tableLines = <String>[line, lines[index + 1]];
        index += 2;
        while (index < lines.length && _isTableLine(lines[index])) {
          tableLines.add(lines[index]);
          index += 1;
        }
        blocks.add(_MobileMarkdownTable(lines: tableLines));
        continue;
      }
      final paragraph = <String>[line];
      index += 1;
      while (index < lines.length &&
          lines[index].trim().isNotEmpty &&
          !lines[index].trimLeft().startsWith('```') &&
          !_isTableLine(lines[index])) {
        paragraph.add(lines[index]);
        index += 1;
      }
      if (paragraph.join('\n').trim().isNotEmpty) {
        blocks.add(_MobileMarkdownParagraph(text: paragraph.join('\n')));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[for (final block in blocks) block],
    );
  }
}

class _MobileMarkdownParagraph extends StatelessWidget {
  const _MobileMarkdownParagraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).textTheme.bodyMedium ?? AleraTokens.monoStyle;
    final spans = _spans(context, text, base);
    final plain =
        spans.length == 1 &&
        spans.single is TextSpan &&
        (spans.single as TextSpan).text == text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: SelectionArea(
        child: plain
            ? Text(text, style: base)
            : RichText(
                text: TextSpan(style: base, children: spans),
              ),
      ),
    );
  }
}

class _MobileCodeBlock extends StatelessWidget {
  const _MobileCodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: SelectionArea(
                child: Text(text, style: AleraTokens.monoStyle),
              ),
            ),
            IconButton(
              tooltip: 'Copy Code',
              onPressed: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: text))),
              icon: const Icon(Icons.copy, size: AleraTokens.iconSm),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MobileMarkdownTable extends StatelessWidget {
  const _MobileMarkdownTable({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final rows = <List<String>>[
      for (final line in lines)
        if (!_isTableDivider(line)) _tableCells(line),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.all(color: AleraTokens.border),
          children: <TableRow>[
            for (final row in rows)
              TableRow(
                children: <Widget>[
                  for (final cell in row)
                    Padding(
                      padding: const EdgeInsets.all(AleraTokens.space6),
                      child: Text(cell),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

List<InlineSpan> _spans(BuildContext context, String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
    r'(!\[[^\]]+\]\([^)]+\)|\[[^\]]+\]\([^)]+\)|\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*]+\*|_[^_]+_)',
  );
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final value = match.group(0)!;
    final image = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(value);
    final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(value);
    if (image != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _MobileInlineImage(alt: image.group(1)!, url: image.group(2)!),
        ),
      );
    } else if (link != null) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _MobileInlineLink(
            label: link.group(1)!,
            url: link.group(2)!,
            style: base.copyWith(
              color: AleraTokens.info,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
    } else if (value.startsWith('`')) {
      spans.add(
        TextSpan(
          text: value.substring(1, value.length - 1),
          style: AleraTokens.monoStyle,
        ),
      );
    } else if (value.startsWith('**') || value.startsWith('__')) {
      spans.add(
        TextSpan(
          text: value.substring(2, value.length - 2),
          style: base.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: value.substring(1, value.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

class _MobileInlineLink extends StatelessWidget {
  const _MobileInlineLink({
    required this.label,
    required this.url,
    required this.style,
  });

  final String label;
  final String url;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => unawaited(_open()),
    child: Text(label, style: style),
  );

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

class _MobileInlineImage extends StatelessWidget {
  const _MobileInlineImage({required this.alt, required this.url});

  final String alt;
  final String url;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: AleraTokens.chatBubbleMaxWidth),
    child: Image.network(
      url,
      semanticLabel: alt,
      errorBuilder: (context, error, stackTrace) => Text(alt),
    ),
  );
}

bool _isTableLine(String line) => line.trimLeft().startsWith('|');

bool _isTableDivider(String line) => _isTableLine(line) && line.contains('---');

List<String> _tableCells(String line) => line
    .trim()
    .replaceFirst(RegExp(r'^\|'), '')
    .replaceFirst(RegExp(r'\|$'), '')
    .split('|')
    .map((cell) => cell.trim())
    .toList(growable: false);
