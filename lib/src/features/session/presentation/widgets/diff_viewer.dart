import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _DiffLineKind { header, added, removed, context, hunk }

class _DiffLine {
  const _DiffLine(this.kind, this.text);
  final _DiffLineKind kind;
  final String text;
}

List<_DiffLine> _parseDiff(String raw) {
  final lines = raw.split('\n');
  final result = <_DiffLine>[];
  for (final line in lines) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      result.add(_DiffLine(_DiffLineKind.header, line));
    } else if (line.startsWith('@@')) {
      result.add(_DiffLine(_DiffLineKind.hunk, line));
    } else if (line.startsWith('+')) {
      result.add(_DiffLine(_DiffLineKind.added, line));
    } else if (line.startsWith('-')) {
      result.add(_DiffLine(_DiffLineKind.removed, line));
    } else {
      result.add(_DiffLine(_DiffLineKind.context, line));
    }
  }
  return result;
}

class DiffViewerDialog extends StatelessWidget {
  const DiffViewerDialog({super.key, required this.diff});

  final String diff;

  static Future<void> show(BuildContext context, String diff) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => DiffViewerDialog(diff: diff),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _parseDiff(diff);
    return Dialog(
      backgroundColor: AleraTokens.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _DiffHeader(diff: diff),
            const Divider(height: 1, color: AleraTokens.border),
            Expanded(
              child: _DiffBody(lines: lines),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffHeader extends StatelessWidget {
  const _DiffHeader({required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space12,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.difference_outlined,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          const Text(
            'File changes',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AleraTokens.foreground,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Copy diff',
            child: InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: diff)),
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              mouseCursor: SystemMouseCursors.click,
              child: const Padding(
                padding: EdgeInsets.all(AleraTokens.space4),
                child: Icon(
                  Icons.content_copy,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            mouseCursor: SystemMouseCursors.click,
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space4),
              child: Icon(
                Icons.close,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffBody extends StatelessWidget {
  const _DiffBody({required this.lines});

  final List<_DiffLine> lines;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return _DiffLineRow(line: line);
      },
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({required this.line});

  final _DiffLine line;

  @override
  Widget build(BuildContext context) {
    final Color? bg;
    final Color textColor;
    switch (line.kind) {
      case _DiffLineKind.added:
        bg = AleraTokens.success.withValues(alpha: 0.12);
        textColor = AleraTokens.success;
      case _DiffLineKind.removed:
        bg = AleraTokens.error.withValues(alpha: 0.10);
        textColor = AleraTokens.error;
      case _DiffLineKind.hunk:
        bg = AleraTokens.accent.withValues(alpha: 0.08);
        textColor = AleraTokens.accent;
      case _DiffLineKind.header:
        bg = AleraTokens.surfaceVariant;
        textColor = AleraTokens.foregroundMuted;
      case _DiffLineKind.context:
        bg = null;
        textColor = AleraTokens.foreground;
    }
    return Container(
      color: bg,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: 1,
      ),
      child: Text(
        line.text,
        style: AleraTokens.monoStyle.copyWith(fontSize: 12, color: textColor),
      ),
    );
  }
}
