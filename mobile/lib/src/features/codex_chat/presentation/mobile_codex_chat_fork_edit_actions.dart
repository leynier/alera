part of 'mobile_codex_chat_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _MobileHistoryActions on _MobileCodexChatScreenState {
  Future<void> _forkHistory({String? turnId}) async {
    try {
      final result = await ref
          .read(
            mobileCodexControllerProvider(widget.hostId, widget.tabId).notifier,
          )
          .forkThread(lastTurnId: turnId);
      if (mounted) {
        widget.onFocusBoundTab?.call(
          result['workspaceId']! as String,
          result['tabId']! as String,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editHistory(MobileCodexTimelineCell cell) async {
    final provider = mobileCodexControllerProvider(widget.hostId, widget.tabId);
    final controller = ref.read(provider.notifier);
    final threadId = controller.threadId;
    final revision = ref.read(provider).value?.historyRevision;
    final operationId = controller.newHistoryOperationId();
    await showDialog<void>(
      context: context,
      builder: (_) => AleraMessageEditor(
        text: cell.markdownText ?? '',
        restartsHistory: true,
        attachmentCount: (cell.metadata['attachments'] as List?)?.length ?? 0,
        onSave: (text) async =>
            await controller.editUserMessage(
              cell,
              text,
              expectedThreadId: threadId,
              operationId: operationId,
              expectedHistoryRevision: revision,
            )
            ? null
            : ref.read(provider).value?.error ??
                  'The message could not be edited.',
      ),
    );
  }
}

class _MobileHistoryMessageActions extends ConsumerWidget {
  const _MobileHistoryMessageActions({required this.cell});
  final MobileCodexTimelineCell cell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = context
        .findAncestorStateOfType<_MobileCodexChatScreenState>();
    if (owner == null || cell.turnId == null) return const SizedBox.shrink();
    final state = ref
        .watch(
          mobileCodexControllerProvider(
            owner.widget.hostId,
            owner.widget.tabId,
          ),
        )
        .value;
    final editable =
        cell.isUser &&
        cell.metadata['isSteering'] != true &&
        cell.metadata['isGoal'] != true;
    return PopupMenuButton<String>(
      tooltip: 'History Actions',
      icon: const Icon(AleraIcons.more, size: AleraTokens.space16),
      onSelected: (action) => unawaited(
        action == 'fork'
            ? owner._forkHistory(turnId: cell.turnId)
            : owner._editHistory(cell),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'fork',
          enabled:
              cell.metadata['isGoal'] != true &&
              state?.supportsFork == true &&
              state?.historyLocked != true &&
              cell.turnId != state?.activeTurnId,
          child: const Text('Fork From Here'),
        ),
        if (editable)
          PopupMenuItem(
            value: 'edit',
            enabled:
                state?.supportsHistoryEdit == true &&
                state?.historyLocked != true,
            child: Tooltip(
              message:
                  state?.queueState['historyEditUnavailableReason']
                      ?.toString() ??
                  'Edit the initial message of this turn',
              child: const Text('Edit Message'),
            ),
          ),
      ],
    );
  }
}
