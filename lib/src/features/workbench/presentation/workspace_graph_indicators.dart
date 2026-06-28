import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

/// Role badge shown next to a workspace name.
///
/// A workspace is either the project's primary worktree, a child of another
/// workspace, or neither — so this renders at most one badge. It mirrors the
/// `Primary` marker that already sits beside the name, keeping role markers
/// visually parallel across the sidebar and the welcome dashboard.
class WorkspaceRoleBadge extends StatelessWidget {
  const WorkspaceRoleBadge({super.key, required this.workspace});

  final Workspace workspace;

  /// Whether [workspace] has a role to show. Callers use this to gate the
  /// adjacent spacer so the predicate lives in one place instead of being
  /// duplicated at every call site.
  static bool hasRole(Workspace workspace) =>
      workspace.isMain || workspace.parentWorkspaceId != null;

  @override
  Widget build(BuildContext context) {
    if (workspace.isMain) {
      return const AleraBadge(label: 'Primary');
    }
    if (workspace.parentWorkspaceId != null) {
      // Info-tinted text so the relationship role reads differently from the
      // neutral "Primary" marker while keeping the same subtle fill.
      return const AleraBadge(
        label: 'Child',
        foregroundColor: AleraTokens.info,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Wrap of low-emphasis chips describing a workspace's place in the graph:
/// the host it runs on (when not local), how many children it has, and its
/// tags. Renders nothing for a plain local workspace with no relationships or
/// tags, so the common case adds no visual weight.
class WorkspaceGraphChips extends StatelessWidget {
  const WorkspaceGraphChips({super.key, required this.workspace});

  final Workspace workspace;

  static const int _maxVisibleTags = 3;

  /// Whether [workspace] has any graph metadata to render. Lets callers gate
  /// surrounding spacing without duplicating the chip logic.
  static bool hasContent(Workspace workspace) {
    final hostId = workspace.hostId.trim();
    if (hostId.isNotEmpty && hostId != 'local') {
      return true;
    }
    if (workspace.childCount > 0) {
      return true;
    }
    return _tagsOf(workspace).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    final hostId = workspace.hostId.trim();
    if (hostId.isNotEmpty && hostId != 'local') {
      chips.add(
        AleraChip(
          leading: AleraIcons.host,
          label: hostId,
          tooltip: 'Host: $hostId',
        ),
      );
    }

    if (workspace.childCount > 0) {
      chips.add(
        AleraChip(
          leading: AleraIcons.gitBranch,
          label: workspace.childCount == 1
              ? '1 Child'
              : '${workspace.childCount} Children',
        ),
      );
    }

    final tags = _tagsOf(workspace);
    for (final tag in tags.take(_maxVisibleTags)) {
      chips.add(
        AleraChip(leading: AleraIcons.tag, label: '#$tag', tooltip: tag),
      );
    }
    final hidden = tags.skip(_maxVisibleTags).toList();
    if (hidden.isNotEmpty) {
      chips.add(
        AleraChip(label: '+${hidden.length} Tags', tooltip: hidden.join(', ')),
      );
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: AleraTokens.space4,
      runSpacing: AleraTokens.space4,
      children: chips,
    );
  }

  /// Prefers human-readable [Workspace.tagNames]; falls back to
  /// [Workspace.tagIds] when names are not available. Blank entries are
  /// dropped before counting, so the `+N Tags` overflow stays accurate.
  static List<String> _tagsOf(Workspace workspace) {
    final source = workspace.tagNames.isNotEmpty
        ? workspace.tagNames
        : workspace.tagIds;
    return source
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}
