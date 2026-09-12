import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceDiffViewerScreen({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final MobileGitChange change,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(workspaceFileBaseName(change.path), overflow: .ellipsis),
      ),
      body: FutureBuilder<MobileGitDiffFile>(
        future: _load(ref),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Text(snapshot.error.toString(), textAlign: .center),
              ),
            );
          }
          final diff = snapshot.data;
          if (diff == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (diff.isBinary) {
            return const Center(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Text('Binary file differences cannot be previewed.'),
              ),
            );
          }
          return ListView.builder(
            padding: AleraTokens.contentPadding,
            itemCount: diff.lines.length + (diff.truncated ? 1 : 0),
            itemBuilder: (context, index) {
              if (diff.truncated && index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space8),
                  child: Text(
                    'Diff truncated.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              final line = diff.lines[diff.truncated ? index - 1 : index];
              return ColoredBox(
                color: switch (line.kind) {
                  'addition' => AleraTokens.success.withValues(alpha: 0.2),
                  'deletion' => AleraTokens.error.withValues(alpha: 0.2),
                  'hunk' => AleraTokens.accentSubtle,
                  _ => Colors.transparent,
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space2,
                  ),
                  child: Text(line.text, style: AleraTokens.monoStyle),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<MobileGitDiffFile> _load(WidgetRef ref) async {
    final client = await ref.read(workspaceClientProvider(hostId).future);
    if (client case final MobileWorkspacePanelsClient panels) {
      return panels.gitDiff(
        workspaceId: workspaceId,
        path: change.path,
        area: change.area,
      );
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to review source control diffs.',
    );
  }
}
