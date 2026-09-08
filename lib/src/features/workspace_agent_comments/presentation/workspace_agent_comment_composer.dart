import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

Future<bool> composeWorkspaceAgentComment(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required WorkspaceAgentCommentKind kind,
  required String path,
  WorkspaceAgentCommentLineRange? lineRange,
  String? hunkHeader,
  String? areaLabel,
  String? snippet,
}) async {
  final location = workspaceAgentCommentLocationLabel(
    WorkspaceAgentComment(
      id: 'draft',
      kind: kind,
      path: path,
      body: '',
      lineRange: lineRange,
      hunkHeader: hunkHeader,
      areaLabel: areaLabel,
    ),
  );
  final body = await showWorkspaceAgentCommentDialog(
    context,
    title: kind == WorkspaceAgentCommentKind.diff
        ? 'Comment on Diff'
        : 'Comment on File',
    path: path,
    locationLabel: location,
    snippet: snippet,
  );
  if (body == null || !context.mounted) {
    return false;
  }
  ref
      .read(workspaceAgentCommentControllerProvider(workspaceId).notifier)
      .add(
        WorkspaceAgentComment(
          id: const Uuid().v4(),
          kind: kind,
          path: path,
          body: body,
          lineRange: lineRange,
          hunkHeader: hunkHeader,
          areaLabel: areaLabel,
          snippet: snippet,
        ),
      );
  return true;
}

Future<bool> composeWorkspaceAgentFileComment(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String path,
  WorkspaceAgentCommentLineRange? lineRange,
  String? snippet,
}) {
  return composeWorkspaceAgentComment(
    context,
    ref,
    workspaceId: workspaceId,
    kind: WorkspaceAgentCommentKind.file,
    path: path,
    lineRange: lineRange,
    snippet: snippet,
  );
}

Future<bool> composeWorkspaceAgentDiffComment(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required String path,
  String? areaLabel,
  String? hunkHeader,
  WorkspaceAgentCommentLineRange? lineRange,
  String? snippet,
}) {
  return composeWorkspaceAgentComment(
    context,
    ref,
    workspaceId: workspaceId,
    kind: WorkspaceAgentCommentKind.diff,
    path: path,
    areaLabel: areaLabel,
    hunkHeader: hunkHeader,
    lineRange: lineRange,
    snippet: snippet,
  );
}

Future<bool> composeWorkspaceAgentDiffLineComment(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
  required GitDiffFile file,
  required int lineIndex,
}) {
  final anchors = workspaceAgentDiffLineAnchors(file.lines);
  if (lineIndex < 0 || lineIndex >= anchors.length) {
    return composeWorkspaceAgentDiffComment(
      context,
      ref,
      workspaceId: workspaceId,
      path: file.path,
      areaLabel: file.area.label,
    );
  }
  final anchor = anchors[lineIndex];
  return composeWorkspaceAgentDiffComment(
    context,
    ref,
    workspaceId: workspaceId,
    path: file.path,
    areaLabel: file.area.label,
    hunkHeader: anchor.hunkHeader,
    lineRange: workspaceAgentCommentRangeForDiffAnchor(anchor),
    snippet: workspaceAgentCommentSnippetForDiffAnchor(
      lines: file.lines,
      anchor: anchor,
    ),
  );
}
