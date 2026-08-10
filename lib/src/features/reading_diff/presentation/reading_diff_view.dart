import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:flutter/material.dart';

class ReadingDiffView extends StatelessWidget {
  const ReadingDiffView({super.key, required this.result});

  final ReadingDiffResult result;

  @override
  Widget build(BuildContext context) {
    final lines = const Utf8Decoder(
      allowMalformed: true,
    ).convert(result.diff).split(RegExp(r'\r?\n'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: AleraTokens.surfaceVariant,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space8,
          ),
          child: Text(
            '${result.summary} Kept ${result.retainedChangedLines}/${result.changedLines} changed lines${result.fromCache ? ' (cached).' : '.'}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: lines.length,
            itemExtent: AleraTokens.space20,
            itemBuilder: (context, index) {
              final line = lines[index];
              return ColoredBox(
                color: _background(line),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                  ),
                  child: SelectableText(
                    line.isEmpty ? ' ' : line,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _foreground(line),
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _background(String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return AleraTokens.codexDiffAdditionBackground;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return AleraTokens.codexDiffDeletionBackground;
    }
    return AleraTokens.bg;
  }

  Color _foreground(String line) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      return AleraTokens.success;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      return AleraTokens.error;
    }
    if (line.startsWith('@@')) {
      return AleraTokens.info;
    }
    return AleraTokens.foreground;
  }
}
