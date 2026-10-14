import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_history.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Puts [text] and [attachments] that came back from the runtime (a failed
/// send, a queued message, a rewound prompt) into [composer], after a draft
/// already there and without duplicating an attachment. Returns whether a
/// draft was there, so the caller can say the text was added to it.
bool appendAgentChatDraft(
  TerminalComposerController composer,
  String text,
  List<AgentChatAttachment> attachments,
) {
  final draft = composer.textController.text;
  final merged = text.isEmpty
      ? draft
      : draft.isEmpty
      ? text
      : '$draft\n\n$text';
  composer.textController.value = TextEditingValue(
    text: merged,
    selection: TextSelection.collapsed(offset: merged.length),
  );
  for (final attachment in attachments) {
    final path = attachment.path;
    if (path == null) continue;
    final kind = attachment.type.isImage
        ? TerminalComposerAttachmentKind.image
        : TerminalComposerAttachmentKind.file;
    if (composer.attachments.any(
      (current) => current.path == path && current.kind == kind,
    )) {
      continue;
    }
    composer.addAttachment(
      kind: kind,
      path: path,
      displayName: attachment.displayName,
      localSourcePath: attachment.localSourcePath,
      attachmentId: attachment.attachmentId,
      sizeBytes: attachment.sizeBytes,
    );
  }
  composer.focusNode.requestFocus();
  return draft.isNotEmpty;
}

/// Which turn history controls the runtime offers; each hides when false.
/// The rewinds also depend on the live session, see [AgentChatRewindOptions].
typedef AgentChatHistorySupport = ({
  bool fork,
  bool diff,
  AgentChatRewindOptions rewind,
});

AgentChatHistorySupport watchAgentChatHistorySupport(
  WidgetRef ref, {
  required AgentChatSession session,
  required AgentChatNativeOperation? pendingOperation,
}) {
  bool supported(String capability) =>
      ref.watch(agentChatCapabilityProvider(capability)).value ?? false;
  return (
    fork: supported(AgentChatWire.forkCapability),
    diff: supported(AgentChatWire.turnDiffCapability),
    rewind: AgentChatRewindOptions.resolve(
      session: session,
      transcriptSupported: supported(AgentChatWire.rewindCapability),
      conversationSupported: supported(AgentChatWire.nativeRewindCapability),
      filesSupported: supported(AgentChatWire.rewindFilesCapability),
      pendingOperation: pendingOperation,
    ),
  );
}

/// Whether two supports offer the same controls; the rewind options are
/// compared by what they offer.
bool sameAgentChatHistorySupport(
  AgentChatHistorySupport a,
  AgentChatHistorySupport b,
) =>
    a.fork == b.fork &&
    a.diff == b.diff &&
    a.rewind.transcript == b.rewind.transcript &&
    a.rewind.conversation == b.rewind.conversation &&
    a.rewind.files == b.rewind.files;

/// Fork, rewind and per-turn changes of a settled turn. Each runs only on the
/// person's press; a fork opens its own tab because they asked for it.
final class AgentChatTurnHistoryActions {
  AgentChatTurnHistoryActions({
    required this.chat,
    required this.composer,
    required this.onOpenFile,
  });

  final AgentChatRef chat;
  final TerminalComposerController composer;
  final ValueChanged<String> onOpenFile;

  Future<void> fork(BuildContext context, WidgetRef ref, String turnId) async {
    try {
      final result = await ref
          .read(agentChatLifecycleRepositoryProvider)
          .fork(
            chat,
            requestId: ref.read(agentChatIdGeneratorProvider)(),
            turnId: turnId,
          );
      final tabId = result.tabId;
      if (tabId == null || !context.mounted) return;
      await ref
          .read(workbenchControllerProvider.notifier)
          .openPersistedWorkspaceTab(
            workspaceId: chat.workspaceId,
            tabId: tabId,
            activateOnlyIfCurrent: true,
          );
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not fork the chat: ${agentChatErrorMessage(error)}',
        tone: .error,
      );
    }
  }

  /// Rewinds Alera's transcript ([AgentChatRewindKind.transcript]) or the
  /// provider's own conversation too ([AgentChatRewindKind.conversation]),
  /// and hands the turn's prompt back to the composer. Files never change.
  Future<void> rewind(
    BuildContext context,
    WidgetRef ref,
    String turnId, {
    AgentChatRewindKind kind = AgentChatRewindKind.transcript,
  }) async {
    if (!await confirmAgentChatRewindKind(context, kind)) return;
    try {
      final lifecycle = ref.read(agentChatLifecycleRepositoryProvider);
      final requestId = ref.read(agentChatIdGeneratorProvider)();
      final result = kind == AgentChatRewindKind.conversation
          ? await lifecycle.nativeHistory.rewind(
              chat,
              requestId: requestId,
              turnId: turnId,
              mode: AgentChatRewindMode.native,
            )
          : await lifecycle.rewind(chat, requestId: requestId, turnId: turnId);
      appendAgentChatDraft(composer, result.prompt, result.attachments);
      AleraToast.publish(message: agentChatRewindResultNotice(result));
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not rewind the chat: ${agentChatErrorMessage(error)}',
        tone: .error,
      );
    }
  }

  /// Puts the files back to the provider's checkpoint before the turn; the
  /// conversation stays as it is.
  Future<void> rewindFiles(
    BuildContext context,
    WidgetRef ref,
    String turnId,
  ) async {
    if (!await confirmAgentChatRewindKind(context, AgentChatRewindKind.files)) {
      return;
    }
    try {
      final result = await ref
          .read(agentChatLifecycleRepositoryProvider)
          .nativeHistory
          .rewindFiles(
            chat,
            requestId: ref.read(agentChatIdGeneratorProvider)(),
            turnId: turnId,
          );
      AleraToast.publish(message: agentChatFileRewindNotice(result));
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not rewind the files: ${agentChatErrorMessage(error)}',
        tone: .error,
      );
    }
  }

  Future<void> showDiff(BuildContext context, WidgetRef ref, String turnId) =>
      showAgentChatTurnDiff(
        context,
        diff: ref
            .read(agentChatLifecycleRepositoryProvider)
            .turnDiff(chat, turnId: turnId),
        onOpenFile: onOpenFile,
      );
}
