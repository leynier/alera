import 'package:alera/src/features/agent_chat/presentation/agent_chat_send_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _button({
  required bool interrupting,
  VoidCallback? onForceStop,
  VoidCallback? onInterrupt,
}) => MaterialApp(
  home: Scaffold(
    body: AgentChatSendOrStopButton(
      hasDraft: false,
      canSend: true,
      busy: true,
      canSteer: false,
      canInterrupt: !interrupting,
      interrupting: interrupting,
      onSend: () {},
      onInterrupt: onInterrupt ?? () {},
      onForceStop: onForceStop,
    ),
  ),
);

void main() {
  testWidgets('a pressed Stop reads Stopping and stays disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_button(interrupting: true));
    expect(find.byTooltip('Stopping…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-chat-force-stop')),
      findsNothing,
    );
  });

  testWidgets('an ignored Stop becomes Force stop', (tester) async {
    var forced = 0;
    await tester.pumpWidget(
      _button(interrupting: true, onForceStop: () => forced += 1),
    );
    final force = find.byKey(const ValueKey<String>('agent-chat-force-stop'));
    expect(force, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('agent-chat-stop')), findsNothing);
    await tester.tap(force);
    expect(forced, 1);
  });
}
