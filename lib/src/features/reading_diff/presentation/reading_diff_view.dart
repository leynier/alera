import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:flutter/material.dart';

enum ReadingDiffViewMode { overview, condensedDiff }

class ReadingDiffView extends StatefulWidget {
  const ReadingDiffView({super.key, required this.result});

  final ReadingDiffResult result;

  @override
  State<ReadingDiffView> createState() => _ReadingDiffViewState();
}

class _ReadingDiffViewState extends State<ReadingDiffView> {
  ReadingDiffViewMode _mode = ReadingDiffViewMode.overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ColoredBox(
          color: AleraTokens.surfaceVariant,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'A reading diff is an AI-guided, non-applicable abbreviation of the original diff.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(height: AleraTokens.space8),
                Align(
                  alignment: Alignment.centerRight,
                  child: AleraSegmentedButton<ReadingDiffViewMode>(
                    dense: true,
                    segments: const <ButtonSegment<ReadingDiffViewMode>>[
                      ButtonSegment<ReadingDiffViewMode>(
                        value: ReadingDiffViewMode.overview,
                        label: Text('Overview'),
                        icon: Icon(AleraIcons.review),
                      ),
                      ButtonSegment<ReadingDiffViewMode>(
                        value: ReadingDiffViewMode.condensedDiff,
                        label: Text('Condensed Diff'),
                        icon: Icon(AleraIcons.diff),
                      ),
                    ],
                    selected: _mode,
                    onSelectionChanged: (mode) => setState(() => _mode = mode),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: switch (_mode) {
            ReadingDiffViewMode.overview => _ReadingDiffOverview(
              result: widget.result,
            ),
            ReadingDiffViewMode.condensedDiff => _ReadingDiffText(
              diff: widget.result.diff,
            ),
          },
        ),
      ],
    );
  }
}

class _ReadingDiffOverview extends StatelessWidget {
  const _ReadingDiffOverview({required this.result});

  final ReadingDiffResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: <Widget>[
        Text('What Changed', style: theme.textTheme.titleMedium),
        const SizedBox(height: AleraTokens.space8),
        SelectableText(result.summary, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space6,
          runSpacing: AleraTokens.space6,
          children: <Widget>[
            AleraChip(label: result.agentLabel, leading: AleraIcons.ai),
            if (result.model case final model?)
              AleraChip(label: model, leading: AleraIcons.agent),
            if (result.effort case final effort?)
              AleraChip(label: '$effort Effort', leading: AleraIcons.plan),
            if (result.chunkCount case final chunkCount?)
              AleraChip(
                label: '$chunkCount ${chunkCount == 1 ? 'Chunk' : 'Chunks'}',
                leading: AleraIcons.contextCompact,
              ),
            AleraChip(
              label:
                  'Kept ${result.retainedChangedLines}/${result.changedLines} Changed Lines',
              leading: AleraIcons.visible,
            ),
            if (result.fromCache)
              const AleraChip(
                label: 'Cached Result',
                leading: AleraIcons.restore,
              ),
          ],
        ),
        if (result.chunkSummaries.length > 1) ...<Widget>[
          const SizedBox(height: AleraTokens.space20),
          Text('Chunk Analysis', style: theme.textTheme.titleSmall),
          const SizedBox(height: AleraTokens.space8),
          for (final chunk in result.chunkSummaries)
            _ReadingDiffChunkSummaryCard(
              chunk: chunk,
              totalChunks: result.chunkSummaries.length,
            ),
        ],
        const SizedBox(height: AleraTokens.space20),
        Container(
          padding: const EdgeInsets.all(AleraTokens.space12),
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          ),
          child: Text(
            'This overview explains the behavioral changes selected while condensing the diff. It does not identify bugs or security findings. Open Condensed Diff to inspect the retained source changes, or return to the original diff for the complete patch.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadingDiffChunkSummaryCard extends StatelessWidget {
  const _ReadingDiffChunkSummaryCard({
    required this.chunk,
    required this.totalChunks,
  });

  final ReadingDiffChunkSummary chunk;
  final int totalChunks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Container(
        padding: const EdgeInsets.all(AleraTokens.space12),
        decoration: BoxDecoration(
          color: AleraTokens.bg,
          border: Border.all(color: AleraTokens.borderSubtle),
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Chunk ${chunk.index + 1} of $totalChunks',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space4),
            SelectableText(
              chunk.summary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingDiffText extends StatelessWidget {
  const _ReadingDiffText({required this.diff});

  final List<int> diff;

  @override
  Widget build(BuildContext context) {
    final lines = const Utf8Decoder(
      allowMalformed: true,
    ).convert(diff).split(RegExp(r'\r?\n'));
    return ListView.builder(
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
