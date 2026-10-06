import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_compose_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks an agent and opens the new question. The inbox switches to Questions
/// first, so returning to it shows that question rather than the agent
/// conversations that were open there before.
Future<void> askAgentAndOpenThread(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  String? workspaceId,
  String? preselectedHandle,
}) async {
  ref
      .read(mobileInboxSectionControllerProvider(hostId).notifier)
      .select(InboxSection.questions);
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
