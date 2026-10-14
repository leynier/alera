import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatSession _session({
  bool busy = false,
  bool rollbackBeforeTurn = true,
  bool rewindFiles = true,
  bool fileCheckpointing = true,
}) => AgentChatSession.fromJson(<String, Object?>{
  'status': busy ? 'running' : 'idle',
  'activeTurnId': ?(busy ? 'turn-1' : null),
  'fileCheckpointing': fileCheckpointing,
  'capabilities': <String, Object?>{
    'nativeHistory': <String, Object?>{
      'rollbackBeforeTurn': rollbackBeforeTurn,
      'rewindFiles': rewindFiles,
      'fileCheckpointing': true,
    },
  },
});

AgentChatNativeOperation _operation({
  String kind = 'rewind',
  Map<String, Object?> recovery = const <String, Object?>{},
}) => AgentChatNativeOperation.fromJson(<String, Object?>{
  'operationId': 'op-1',
  'state': 'uncertain',
  'kind': kind,
  'recovery': recovery,
});

void main() {
  group('AgentChatRewindOptions', () {
    test('each rewind needs its host verb and the adapter proof', () {
      final all = AgentChatRewindOptions.resolve(
        session: _session(),
        transcriptSupported: true,
        conversationSupported: true,
        filesSupported: true,
      );
      expect(all.kinds, <AgentChatRewindKind>[
        AgentChatRewindKind.conversation,
        AgentChatRewindKind.transcript,
        AgentChatRewindKind.files,
      ]);

      final noProof = AgentChatRewindOptions.resolve(
        session: _session(rollbackBeforeTurn: false, rewindFiles: false),
        transcriptSupported: true,
        conversationSupported: true,
        filesSupported: true,
      );
      expect(noProof.kinds, <AgentChatRewindKind>[
        AgentChatRewindKind.transcript,
      ]);

      // Support alone is not enough: checkpointing must be enabled.
      final disabled = AgentChatRewindOptions.resolve(
        session: _session(fileCheckpointing: false),
        transcriptSupported: false,
        conversationSupported: false,
        filesSupported: true,
      );
      expect(disabled.any, isFalse);
    });

    test('nothing is offered while busy or with an operation pending', () {
      expect(
        AgentChatRewindOptions.resolve(
          session: _session(busy: true),
          transcriptSupported: true,
          conversationSupported: true,
          filesSupported: true,
        ).any,
        isFalse,
      );
      expect(
        AgentChatRewindOptions.resolve(
          session: _session(),
          transcriptSupported: true,
          conversationSupported: true,
          filesSupported: true,
          pendingOperation: _operation(),
        ).any,
        isFalse,
      );
    });
  });

  group('rewind notices', () {
    test('transcript and conversation results repeat only the evidence', () {
      AgentChatRewindResult result(bool? reverted) => AgentChatRewindResult(
        snapshot: AgentChatSnapshot(chatId: 'c', workspaceId: 'w', cursor: 1),
        prompt: '',
        filesystemChangesReverted: reverted,
      );
      expect(agentChatRewindResultNotice(result(false)), contains('Files stay'));
      expect(agentChatRewindResultNotice(result(true)), contains('reverted'));
      expect(agentChatRewindResultNotice(result(null)), contains('not verified'));
    });

    test('a file rewind acknowledgement alone never reads as restored', () {
      expect(
        agentChatFileRewindNotice(
          const AgentChatFilesystemRewindResult(
            filesystemRewindAcknowledged: true,
          ),
        ),
        contains('not confirmed'),
      );
      expect(
        agentChatFileRewindNotice(
          const AgentChatFilesystemRewindResult(
            filesystemRewindAcknowledged: true,
            filesystemChangesReverted: true,
          ),
        ),
        'Files were restored to the checkpoint.',
      );
      expect(
        agentChatFileRewindNotice(const AgentChatFilesystemRewindResult()),
        contains('not verified'),
      );
    });
  });

  group('native operation recovery', () {
    test('offers exactly the allowed actions in a fixed order', () {
      final operation = _operation(
        recovery: <String, Object?>{
          'needsReconciliation': true,
          'canCancelUnstarted': true,
          'canRestartFromTranscript': true,
          'canFinishAcknowledged': true,
          'canContinueFromCurrentFiles': true,
          'message': 'The provider did not answer.',
        },
      );
      // Keeping the current files only applies to a file rewind.
      expect(agentChatNativeOperationActions(operation), <AgentChatNativeHistoryAction>[
        AgentChatNativeHistoryAction.finishAcknowledged,
        AgentChatNativeHistoryAction.restartFromTranscript,
        AgentChatNativeHistoryAction.cancelUnstarted,
      ]);
      expect(agentChatNativeOperationTitle(operation), 'Rewind Needs a Decision');
      expect(
        agentChatNativeOperationMessage(operation),
        'The provider did not answer.',
      );
    });

    test('a file rewind can keep the current files', () {
      final operation = _operation(
        kind: 'rewindFiles',
        recovery: <String, Object?>{
          'needsReconciliation': true,
          'canContinueFromCurrentFiles': true,
        },
      );
      expect(agentChatNativeOperationActions(operation), <AgentChatNativeHistoryAction>[
        AgentChatNativeHistoryAction.continueFromCurrentFiles,
      ]);
      expect(
        agentChatNativeOperationTitle(operation),
        'File Rewind Needs a Decision',
      );
    });

    test('an operation without recovery offers nothing and pauses send', () {
      final operation = AgentChatNativeOperation.fromJson(<String, Object?>{
        'operationId': 'op-2',
        'state': 'executing',
        'kind': 'rewind',
      });
      expect(agentChatNativeOperationActions(operation), isEmpty);
      expect(agentChatNativeOperationTitle(operation), 'Rewinding Conversation');
      expect(
        agentChatNativeOperationMessage(operation),
        agentChatNativeOperationSendBlockedHint,
      );
    });
  });
}
