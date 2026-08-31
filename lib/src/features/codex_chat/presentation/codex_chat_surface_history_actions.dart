part of 'codex_chat_surface.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _CodexHistoryActions on _CodexChatSurfaceState {
  Future<void> _forkHistory({String? turnId}) async {
    try {
      final result = await ref
          .read(codexChatControllerProvider(widget.tab.id).notifier)
          .forkThread(lastTurnId: turnId);
      if (!mounted) return;
      await ref
          .read(workbenchControllerProvider.notifier)
          .openPersistedWorkspaceTab(
            workspaceId: result['workspaceId']! as String,
            tabId: result['tabId']! as String,
          );
    } catch (error) {
      if (mounted) AleraToast.show(context, message: error.toString());
    }
  }

  Future<void> _editHistory(CodexTimelineCell cell) async {
    final provider = codexChatControllerProvider(widget.tab.id);
    final controller = ref.read(provider.notifier);
    final threadId = controller.threadId;
    final revision = ref.read(provider).historyRevision;
    final operationId = const Uuid().v4();
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
            : ref.read(provider).error ?? 'The message could not be edited.',
      ),
    );
  }
}

class _CodexHistoryMessageActions extends ConsumerWidget {
  const _CodexHistoryMessageActions({required this.cell});
  final CodexTimelineCell cell;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = context.findAncestorStateOfType<_CodexChatSurfaceState>();
    if (owner == null || cell.turnId == null) return const SizedBox.shrink();
    final state = ref.watch(codexChatControllerProvider(owner.widget.tab.id));
    final editable =
        cell.kind == CodexTimelineKind.userMessage &&
        cell.metadata['isSteering'] != true &&
        cell.metadata['isGoal'] != true;
    return PopupMenuButton<String>(
      tooltip: 'History Actions',
      icon: const Icon(AleraIcons.more, size: AleraTokens.iconSm),
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
              state.supportsFork &&
              !state.historyLocked &&
              cell.turnId != state.snapshot.activeTurnId,
          child: const Text('Fork From Here'),
        ),
        if (editable)
          PopupMenuItem(
            value: 'edit',
            enabled: state.supportsHistoryEdit && !state.historyLocked,
            child: Tooltip(
              message:
                  state.queueState['historyEditUnavailableReason']
                      ?.toString() ??
                  'Edit the initial message of this turn',
              child: const Text('Edit Message'),
            ),
          ),
      ],
    );
  }
}
