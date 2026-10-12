import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

/// Physical location marker, independent of task priority or parentage.
class const WorkspaceRoleBadge({super.key, required final Workspace workspace})
    extends StatelessWidget {
  /// Whether [workspace] has a role to show. Callers use this to gate the
  /// adjacent spacer so the predicate lives in one place instead of being
  /// duplicated at every call site.
  static bool hasRole(Workspace workspace) => true;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: workspace.isMain ? 'Project folder' : 'Linked worktree',
      child: workspace.isMain
          ? const Icon(
              AleraIcons.workspaceMain,
              size: 12,
              color: AleraTokens.foregroundMuted,
            )
          : const AleraLinkedWorktreeIcon(),
    );
  }
}
