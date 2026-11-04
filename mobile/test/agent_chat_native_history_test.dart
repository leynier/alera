import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_native_history_banner.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_native_history_rewind_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: buildAleraMobileDarkTheme(),
    home: Scaffold(body: child),
  ),
);

AgentChatNativeOperation _operation(Map<String, Object?> recovery) =>
    AgentChatNativeOperation.fromJson(<String, Object?>{
      'operationId': 'op-1',
      'state': 'uncertain',
      'kind': 'rewindFiles',
      'recovery': recovery,
    });

void main() {
  testWidgets('the banner offers only the allowed actions, each confirmed', (
    tester,
  ) async {
    final chosen = <AgentChatNativeHistoryAction>[];
    await _pump(
      tester,
      AgentChatNativeOperationBanner(
        operation: _operation(<String, Object?>{
          'needsReconciliation': true,
          'canContinueFromCurrentFiles': true,
          'message': 'The provider did not report the file rewind.',
        }),
        enabled: true,
        busy: false,
        onAction: chosen.add,
      ),
    );
    expect(find.text('File Rewind Needs a Decision'), findsOneWidget);
    expect(
      find.text('The provider did not report the file rewind.'),
      findsOneWidget,
    );
    expect(find.text('Keep Current Files'), findsOneWidget);
    expect(find.text('Restart From Transcript'), findsNothing);

    await tester.tap(find.text('Keep Current Files'));
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);
    await tester.tap(find.text('Keep Current Files').last);
    await tester.pumpAndSettle();
    expect(chosen, <AgentChatNativeHistoryAction>[
      AgentChatNativeHistoryAction.continueFromCurrentFiles,
    ]);
  });

  testWidgets('a busy banner disables its actions', (tester) async {
    await _pump(
      tester,
      AgentChatNativeOperationBanner(
        operation: _operation(<String, Object?>{
          'needsReconciliation': true,
          'canContinueFromCurrentFiles': true,
        }),
        enabled: true,
        busy: true,
        onAction: (_) => fail('A busy banner must not act.'),
      ),
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Keep Current Files'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('the rewind sheet returns only a confirmed choice', (
    tester,
  ) async {
    AgentChatRewindKind? result;
    var finished = false;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showAgentChatRewindSheet(
              context,
              options: const AgentChatRewindOptions(
                transcript: true,
                conversation: true,
              ),
            );
            finished = true;
          },
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rewind Conversation'), findsOneWidget);
    expect(find.text('Rewind Transcript'), findsOneWidget);
    expect(find.text('Rewind Files'), findsNothing);

    await tester.tap(find.text('Rewind Transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Rewind Transcript?'), findsOneWidget);
    await tester.tap(find.text('Rewind'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(result, AgentChatRewindKind.transcript);
  });

  testWidgets('a single choice goes straight to the confirmation', (
    tester,
  ) async {
    AgentChatRewindKind? result = AgentChatRewindKind.transcript;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showAgentChatRewindSheet(
            context,
            options: const AgentChatRewindOptions(files: true),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Rewind Files?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
