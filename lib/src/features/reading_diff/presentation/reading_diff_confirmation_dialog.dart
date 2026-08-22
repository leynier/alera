import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/reading_diff/domain/reading_diff_models.dart';
import 'package:flutter/material.dart';

class ReadingDiffConfirmationDialog extends StatelessWidget {
  const ReadingDiffConfirmationDialog({super.key, required this.preparation});

  final ReadingDiffPreparation preparation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.sidebarMaxWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.ai, size: AleraTokens.space20),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Generate Reading Diff',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      'This manually runs the configured AI Text agent and may consume subscription quota or other provider usage. The complete selected patch is provided, including portions hidden by preview truncation.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space8),
                    Text(
                      'The result opens with a behavioral overview and a condensed, non-applicable diff. It is not a bug or security review.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    _ReadingDiffDetail(
                      label: 'Agent',
                      value: preparation.agent.label,
                    ),
                    _ReadingDiffDetail(
                      label: 'Model',
                      value: preparation.model,
                    ),
                    _ReadingDiffDetail(
                      label: 'Effort',
                      value: preparation.effort ?? 'Agent Default',
                    ),
                    _ReadingDiffDetail(
                      label: 'Access',
                      value:
                          preparation.accessPolicy ==
                              AgentTaskAccessPolicy.repositoryReadOnly
                          ? 'Repository Read Only'
                          : 'Diff Only',
                    ),
                    _ReadingDiffDetail(
                      label: 'Diff Size',
                      value: _formatBytes(preparation.rawBytes),
                    ),
                    _ReadingDiffDetail(
                      label: 'Chunks',
                      value: preparation.chunkCount.toString(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Generate Reading Diff'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingDiffDetail extends StatelessWidget {
  const _ReadingDiffDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: AleraTokens.space48 * 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'JetBrains Mono'),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KiB';
  }
  return '${(kib / 1024).toStringAsFixed(1)} MiB';
}
