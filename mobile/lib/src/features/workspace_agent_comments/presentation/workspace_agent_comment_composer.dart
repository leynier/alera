import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<bool> composeWorkspaceAgentComment(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
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
      .read(
        workspaceAgentCommentControllerProvider(hostId, workspaceId).notifier,
      )
      .add(
        path: path,
        body: body,
        kind: kind,
        lineRange: lineRange,
        hunkHeader: hunkHeader,
        areaLabel: areaLabel,
        snippet: snippet,
      );
  return true;
}

Future<bool> composeWorkspaceAgentDiffComment(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
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
    hostId: hostId,
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
  required String hostId,
  required String workspaceId,
  required MobileGitDiffFile file,
  required int lineIndex,
}) {
  final areaLabel = workspaceAgentCommentAreaLabel(file.area);
  final anchors = workspaceAgentDiffLineAnchors(file.lines);
  if (lineIndex < 0 || lineIndex >= anchors.length) {
    return composeWorkspaceAgentDiffComment(
      context,
      ref,
      hostId: hostId,
      workspaceId: workspaceId,
      path: file.path,
      areaLabel: areaLabel,
    );
  }
  final anchor = anchors[lineIndex];
  return composeWorkspaceAgentDiffComment(
    context,
    ref,
    hostId: hostId,
    workspaceId: workspaceId,
    path: file.path,
    areaLabel: areaLabel,
    hunkHeader: anchor.hunkHeader,
    lineRange: workspaceAgentCommentRangeForDiffAnchor(anchor),
    snippet: workspaceAgentCommentSnippetForDiffAnchor(
      lines: file.lines,
      anchor: anchor,
    ),
  );
}
