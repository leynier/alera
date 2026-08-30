import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/reading_diff/application/reading_diff_generation_progress.dart';
import 'package:flutter/material.dart';

class ReadingDiffGenerationProgressView extends StatelessWidget {
  const ReadingDiffGenerationProgressView({
    super.key,
    required this.progress,
    this.agentLabel,
    this.model,
  });

  final ReadingDiffGenerationProgress progress;
  final String? agentLabel;
  final String? model;

  @override
  Widget build(BuildContext context) {
    final detail = <String>[?agentLabel, ?model].join(' · ');
    return ColoredBox(
      color: AleraTokens.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: AleraTokens.space16,
              height: AleraTokens.space16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    progress.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    progress.description,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                  if (detail.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AleraTokens.space2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                  const SizedBox(height: AleraTokens.space6),
                  LinearProgressIndicator(value: progress.fraction),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
