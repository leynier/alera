import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/layout/alera_confirm_dialog.dart';
import '../application/codex_chat_controller.dart';

typedef CodexQueueCancellation = Future<void> Function();

Future<bool> confirmCodexQueueClose(
  BuildContext context,
  WidgetRef ref,
  String tabId,
) async {
  final cancel = await prepareCodexQueueClose(context, ref, tabId);
  if (cancel == null) return false;
  await cancel();
  return true;
}

Future<CodexQueueCancellation?> prepareCodexQueueClose(
  BuildContext context,
  WidgetRef ref,
  String tabId,
) async {
  final host = ref.read(codexChatHostClientProvider);
  if (!await host.supportsSharedQueue()) {
    if (!context.mounted) return null;
    final container = ProviderScope.containerOf(context, listen: false);
    final provider = codexChatControllerProvider(tabId);
    if (!container.exists(provider) ||
        container.read(provider).queuedMessages.isEmpty) {
      return () async {};
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => const AleraConfirmDialog(
            title: 'Cancel Queued Messages?',
            message: 'Closing this tab cancels its locally queued messages.',
            confirmLabel: 'Cancel Messages And Close',
            destructive: true,
          ),
        ) ==
        true;
    return confirmed ? () async {} : null;
  }
  final queue = await host.request('codex.queue.get', {'tabId': tabId});
  if ((queue['messages'] as List? ?? const []).isEmpty &&
      (queue['otherQueues'] as List? ?? const []).isEmpty) {
    return () async {};
  }
  if (!context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AleraConfirmDialog(
      title: 'Cancel Queued Messages?',
      message:
          'Closing this tab cancels its pending messages for every connected client.',
      confirmLabel: 'Cancel Messages And Close',
      destructive: true,
    ),
  );
  if (confirmed != true) return null;
  return () async {
    await host.request('codex.queue.cancel', {
      'tabId': tabId,
      'expectedThreadId': queue['threadId'] == '' ? null : queue['threadId'],
      'expectedRevision': queue['revision'],
      'otherQueues': queue['otherQueues'],
    });
  };
}
