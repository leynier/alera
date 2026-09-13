import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_relocation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> showWorkspaceRelocationDialog(
  BuildContext context, {
  required String hostId,
  required WorkspaceSummary workspace,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          WorkspaceRelocationDialog(hostId: hostId, workspace: workspace),
    ) ==
    true;

class const WorkspaceRelocationDialog({
  super.key,
  required final String hostId,
  required final WorkspaceSummary workspace,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workspaceRelocationControllerProvider(
      hostId,
      workspace.id,
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final action = workspace.isMain ? 'Hand Off' : 'Hand On';
    final theme = Theme.of(context);
    return PopScope(
      canPop: !state.busy,
      child: AleraDialog(
        maxWidth: AleraTokens.emptyStateMaxWidth,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  workspace.isMain
                      ? 'Hand Off to Worktree'
                      : 'Hand On to Project Folder',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AleraTokens.space12),
                Text(
                  workspace.isMain
                      ? 'Move this task to its own worktree. Its identity and tabs are preserved. Stop its processes before continuing.'
                      : 'Move this task to the project folder. That folder must be clean, and affected editors must be saved. Every task there shares the resulting branch and files. Stop this task’s processes first; its old worktree is removed after the move succeeds.',
                ),
                if (workspace.isMain) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Move Current Branch'),
                    subtitle: Text(
                      workspace.branch ?? 'The branch is unavailable',
                    ),
                    value: state.useCurrentBranch,
                    onChanged: state.busy
                        ? null
                        : (value) =>
                              controller.edit(useCurrentBranch: value ?? false),
                  ),
                  if (!state.useCurrentBranch)
                    TextFormField(
                      key: const ValueKey('new-branch'),
                      initialValue: state.branch,
                      enabled: !state.busy,
                      decoration: const InputDecoration(
                        labelText: 'New Branch',
                      ),
                      onChanged: (value) => controller.edit(branch: value),
                    ),
                  if (state.useCurrentBranch)
                    TextFormField(
                      key: const ValueKey('replacement-branch'),
                      initialValue: state.replacementBranch,
                      enabled: !state.busy,
                      decoration: const InputDecoration(
                        labelText: 'Replacement Branch',
                        helperText: 'An existing branch to leave on the shared project folder.',
                      ),
                      onChanged: (value) =>
                          controller.edit(replacementBranch: value),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Move All Transferable Changes'),
                    subtitle: Text(
                      state.useCurrentBranch
                          ? 'Required when moving the current branch.'
                          : 'Includes changes shared by every task on the project folder. Unchecked leaves them there.',
                    ),
                    value: state.moveChanges,
                    onChanged: state.busy || state.useCurrentBranch
                        ? null
                        : (value) =>
                              controller.edit(moveChanges: value ?? false),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Confirm Shared Impact'),
                  subtitle: const Text(
                    'I understand how these choices affect other tasks sharing this folder.',
                  ),
                  value: state.confirmed,
                  onChanged: state.busy
                      ? null
                      : (value) => controller.confirm(value ?? false),
                ),
                if (state.error case final error?) ...[
                  Text(
                    error,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: state.busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space12),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.busy || !state.confirmed
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final completed = await controller.submit(
                                  workspace,
                                );
                                if (completed && context.mounted) {
                                  final warning = ref.read(provider).warning;
                                  if (warning != null) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(warning)),
                                    );
                                  }
                                  Navigator.of(context).pop(true);
                                }
                              },
                        child: Text(
                          state.busy
                              ? 'Moving…'
                              : state.error != null
                              ? 'Retry'
                              : action,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
