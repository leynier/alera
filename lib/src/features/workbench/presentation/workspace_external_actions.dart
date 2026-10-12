import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/workbench/application/repository_browser_opener.dart';
import 'package:alera/src/features/workbench/application/repository_browser_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> openWorkspaceFolder(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  if (workspace.isRemote) {
    AleraToast.show(
      context,
      message:
          'This folder is on another host. Copy its path to open it there.',
      tone: .info,
    );
    return;
  }
  final result = await ref
      .read(workspaceFolderOpenerProvider)
      .open(workspace.path);
  if (!result.ok && context.mounted) {
    AleraToast.show(
      context,
      message: result.message ?? 'Could not open workspace folder.',
      tone: .error,
    );
  }
}

Future<void> copyWorkspacePath(
  BuildContext context,
  Workspace workspace,
) async {
  await Clipboard.setData(ClipboardData(text: workspace.path));
  if (context.mounted) {
    AleraToast.show(context, message: 'Workspace path copied', tone: .success);
  }
}

Future<void> openWorkspaceInBrowser(
  BuildContext context,
  WidgetRef ref,
  Workspace workspace,
) async {
  final opener = ref.read(repositoryBrowserOpenerProvider);
  GitHostingProvider? override;
  try {
    override = await ref
        .read(
          effectiveHostingProviderOverrideProvider(workspace.projectId).future,
        )
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    override = null;
  }
  try {
    final result = await opener.open(
      repoPath: workspace.path,
      override: override,
    );
    if (!context.mounted || result == OpenRepositoryOutcome.opened) return;
    AleraToast.show(
      context,
      message: switch (result) {
        OpenRepositoryOutcome.noRemote =>
          'No git remote configured for this workspace.',
        OpenRepositoryOutcome.undetectable =>
          'Could not detect a supported git hosting provider.',
        _ => 'Could not open the browser.',
      },
      tone: .info,
    );
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: 'Could not open the repository: $error',
        tone: .error,
      );
    }
  }
}
