import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_approval_history.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_native_history_notice.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_history.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _ignore(String _) {}

void _noop() {}

AgentChatTimelineActions _actions({
  ValueChanged<String>? fork,
  ValueChanged<String>? rewind,
  ValueChanged<String>? diff,
  ValueChanged<String>? nativeRewind,
  ValueChanged<String>? rewindFiles,
}) => AgentChatTimelineActions(
  chatId: 'chat-1',
  onRetrySend: _ignore,
  onEditSend: _ignore,
  onOpenLink: _ignore,
  onOpenFile: _ignore,
  onImplementPlan: _noop,
  onForkTurn: fork,
  onRewindTurn: rewind,
  onShowTurnDiff: diff,
  onNativeRewindTurn: nativeRewind,
  onRewindFilesTurn: rewindFiles,
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('no control shows when the runtime offers none', (tester) async {
    await _pump(
      tester,
      AgentChatTurnHistoryMenu(turnId: 't1', actions: _actions()),
    );
    expect(find.byTooltip('Turn Actions'), findsNothing);
    expect(AgentChatTurnHistoryMenu.offers(_actions()), isFalse);
  });

  testWidgets('only the offered controls show and report the turn', (
    tester,
  ) async {
    final forked = <String>[];
    await _pump(
      tester,
      AgentChatTurnHistoryMenu(
        turnId: 't1',
        actions: _actions(fork: forked.add, diff: _ignore),
      ),
    );
    await tester.tap(find.byTooltip('Turn Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Fork From Here'), findsOneWidget);
    expect(find.text('View Changes'), findsOneWidget);
    expect(find.text('Rewind Transcript'), findsNothing);
    expect(find.text('Rewind Conversation'), findsNothing);
    await tester.tap(find.text('Fork From Here'));
    await tester.pumpAndSettle();
    expect(forked, <String>['t1']);
  });

  testWidgets('each rewind kind is its own clearly named control', (
    tester,
  ) async {
    final calls = <String>[];
    await _pump(
      tester,
      AgentChatTurnHistoryMenu(
        turnId: 't1',
        actions: _actions(
          rewind: (id) => calls.add('transcript:$id'),
          nativeRewind: (id) => calls.add('conversation:$id'),
          rewindFiles: (id) => calls.add('files:$id'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Turn Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rewind Conversation'), findsOneWidget);
    expect(find.text('Rewind Transcript'), findsOneWidget);
    expect(find.text('Rewind Files'), findsOneWidget);
    await tester.tap(find.text('Rewind Files'));
    await tester.pumpAndSettle();
    expect(calls, <String>['files:t1']);
  });

  testWidgets('a pending native operation offers only allowed actions', (
    tester,
  ) async {
    final chosen = <AgentChatNativeHistoryAction>[];
    final operation = AgentChatNativeOperation.fromJson(<String, Object?>{
      'operationId': 'op-1',
      'state': 'uncertain',
      'kind': 'rewind',
      'recovery': <String, Object?>{
        'needsReconciliation': true,
        'canRestartFromTranscript': true,
        'canCancelUnstarted': false,
        'message': 'The provider did not confirm the rollback.',
      },
    });
    Future<void> pumpNotice({required bool busy}) => _pump(
      tester,
      SizedBox(
        width: 520,
        child: AgentChatNativeOperationNotice(
          operation: operation,
          enabled: true,
          busy: busy,
          onAction: chosen.add,
        ),
      ),
    );
    await pumpNotice(busy: false);
    expect(
      find.textContaining('The provider did not confirm the rollback.'),
      findsOneWidget,
    );
    expect(find.text('Restart From Transcript'), findsOneWidget);
    expect(find.text('Cancel Rewind'), findsNothing);
    expect(find.text('Finish Rewind'), findsNothing);

    // Choosing asks first; backing out sends nothing.
    await tester.tap(find.text('Restart From Transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);

    await tester.tap(find.text('Restart From Transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restart From Transcript').last);
    await tester.pumpAndSettle();
    expect(chosen, <AgentChatNativeHistoryAction>[
      AgentChatNativeHistoryAction.restartFromTranscript,
    ]);

    // While the choice is on its way nothing can be chosen again.
    await pumpNotice(busy: true);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(
              const ValueKey<String>(
                'agent-chat-native-action-restartFromTranscript',
              ),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('an unavailable turn diff never reads as no changes', (
    tester,
  ) async {
    await _pump(
      tester,
      AgentChatTurnDiffView(
        diff: Future<AgentChatTurnDiff>.value(
          const AgentChatTurnDiff(turnId: 't1', reason: 'Codex sent none.'),
        ),
        onOpenFile: _ignore,
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'The provider did not report changes for this turn. Codex sent none.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('approval history pages back through older requests', (
    tester,
  ) async {
    final asked = <String?>[];
    AgentChatItem record(String id, String title, String decision) =>
        AgentChatItem.fromJson(<String, Object?>{
          'itemId': id,
          'type': 'notice',
          'status': 'completed',
          'createdAt': '2026-10-12T10:00:00Z',
          'updatedAt': '2026-10-12T10:01:00Z',
          'title': title,
          'actor': 'mobile:phone',
          'normalized': <String, Object?>{
            'approvalHistory': <String, Object?>{
              'requestId': id,
              'kind': 'commandExecutionApproval',
              'status': 'resolved',
              'response': <String, Object?>{
                'type': 'approval',
                'decision': decision,
              },
            },
          },
        });
    await _pump(
      tester,
      SizedBox(
        width: 480,
        height: 480,
        child: AgentChatApprovalHistoryView(
          load: (before) async {
            asked.add(before);
            return before == null
                ? AgentChatApprovalHistoryPage(
                    items: <AgentChatItem>[record('r2', 'Run tests', 'accept')],
                    historyBefore: 'seq:4',
                  )
                : AgentChatApprovalHistoryPage(
                    items: <AgentChatItem>[record('r1', 'Delete', 'decline')],
                    scanLimited: true,
                  );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Run tests'), findsOneWidget);
    expect(find.text('Allow Once'), findsOneWidget);
    expect(find.textContaining('From Phone'), findsOneWidget);

    await tester.tap(find.text('Load Older Requests'));
    await tester.pump();
    expect(asked, <String?>[null, 'seq:4']);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Load Older Requests'), findsNothing);
    expect(find.textContaining('Only recent history'), findsOneWidget);
  });
}
