import 'package:alera/src/features/error_reporting/application/user_facing_error_message.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter/material.dart';

class const WorkspaceComparisonDialog({
  super.key,
  required this.git,
  required this.path,
  required this.comparison,
  this.initialFile,
}) extends StatefulWidget {
  final String? initialFile;
  final GitBackend git;
  final String path;
  final GitWorkspaceComparison comparison;
  @override
  State<WorkspaceComparisonDialog> createState() =>
      _WorkspaceComparisonDialogState();
}

class _WorkspaceComparisonDialogState extends State<WorkspaceComparisonDialog> {
  GitChangeEntry? _selected;
  Future<GitDiffResult>? _diff;
  @override
  void initState() {
    super.initState();
    _selected = widget.comparison.entries
        .where((entry) => entry.path == widget.initialFile)
        .firstOrNull;
    if (_selected != null) {
      _diff = widget.git.workspaceComparisonDiff(
        widget.path,
        widget.comparison,
        _selected!.path,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AleraDialog(
    maxWidth: AleraTokens.dialogWideWidth,
    maxHeight: AleraTokens.dialogMaxHeight,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Changes', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Compare against ${widget.comparison.baseRef ?? 'HEAD'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AleraTokens.space12),
          if (_selected == null)
            Flexible(
              child: widget.comparison.entries.isEmpty
                  ? const Text('No changes')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.comparison.entries.length,
                      itemBuilder: (context, index) {
                        final entry = widget.comparison.entries[index];
                        return ListTile(
                          dense: true,
                          title: Text(entry.path),
                          trailing: Text(
                            entry.isBinary
                                ? 'Binary'
                                : '+${entry.added ?? 0} -${entry.removed ?? 0}',
                          ),
                          onTap: () => setState(() {
                            _selected = entry;
                            _diff = widget.git.workspaceComparisonDiff(
                              widget.path,
                              widget.comparison,
                              entry.path,
                            );
                          }),
                        );
                      },
                    ),
            )
          else ...[
            Text(_selected!.path, style: Theme.of(context).textTheme.bodySmall),
            Flexible(
              child: FutureBuilder<GitDiffResult>(
                future: _diff,
                builder: (context, result) {
                  if (result.hasError) {
                    return Text(userFacingErrorMessage(result.error));
                  }
                  if (!result.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final file = result.data!.files.first;
                  if (file.isBinary) return const Text('Binary file changed');
                  return Column(
                    children: [
                      if (result.data!.truncated)
                        const Text('Diff preview truncated.'),
                      Expanded(
                        child: ListView.builder(
                          itemCount: file.lines.length,
                          itemBuilder: (context, index) {
                            final line = file.lines[index];
                            return Text(
                              line.text,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: 'JetBrains Mono',
                                    color: switch (line.kind) {
                                      GitDiffLineKind.addition =>
                                        AleraTokens.success,
                                      GitDiffLineKind.deletion =>
                                        AleraTokens.error,
                                      _ => AleraTokens.foreground,
                                    },
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_selected != null)
                TextButton(
                  onPressed: () => setState(() => _selected = null),
                  child: const Text('Back'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
