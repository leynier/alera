import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_launcher.dart';
import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<AgentTaskDispatchResult?> dispatchWorkspaceAgentComments(
  BuildContext context,
  WidgetRef ref, {
  required String workspaceId,
}) async {
  final comments = ref.read(
    workspaceAgentCommentControllerProvider(workspaceId),
  );
  final request = workspaceAgentCommentDispatchRequest(
    workspaceId: workspaceId,
    comments: comments,
  );
  if (request == null) {
    AleraToast.show(
      context,
      message: 'Add a comment before sending.',
      tone: .error,
    );
    return null;
  }
  try {
    await ref.read(agentProfilesProvider.future);
  } on Object catch (error) {
    if (context.mounted) {
      AleraToast.show(context, message: error.toString(), tone: .error);
    }
    return null;
  }
  if (!context.mounted) {
    return null;
  }
  final result = await showAgentTaskDispatchFlow(
    context,
    ref,
    request: request,
  );
  if (result != null) {
    ref
        .read(workspaceAgentCommentControllerProvider(workspaceId).notifier)
        .clear();
  }
  return result;
}
