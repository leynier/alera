import 'package:alera_mobile/src/features/inbox/presentation/inbox_compose_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:alera_mobile/src/features/runs/application/activity_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks an agent and opens the new question. Activity switches to Questions
/// first, so returning to it shows that question rather than whatever part
/// was open there before.
Future<void> askAgentAndOpenThread(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  String? workspaceId,
  String? preselectedHandle,
}) async {
  ref
      .read(mobileActivitySectionControllerProvider(hostId).notifier)
      .select(ActivitySection.questions);
  final threadId = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      builder: (_) => InboxComposeScreen(
        hostId: hostId,
        workspaceId: workspaceId,
        preselectedHandle: preselectedHandle,
      ),
    ),
  );
  if (threadId == null || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => InboxThreadScreen(hostId: hostId, threadId: threadId),
    ),
  );
}
