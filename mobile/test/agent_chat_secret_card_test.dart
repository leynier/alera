import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _value = 'synthetic-test-value';

AgentChatRequest _secret() => AgentChatRequest.fromJson(<String, Object?>{
  'requestId': 'secret-1',
  'kind': 'secret_input',
  'createdAt': '2026-11-02T10:00:00Z',
  'title': 'Deploy token',
  'detail': 'To deploy the preview.',
  'masked': true,
  'questions': <Object?>[
    <String, Object?>{'id': 'value', 'placeholder': 'ghp_...'},
  ],
});

Widget _dock(List<AgentChatResponse> responses) => MaterialApp(
  home: Scaffold(
    body: AgentChatRequestDock(
      requests: <AgentChatRequest>[_secret()],
      enabled: true,
      respondingRequestIds: const <String>{},
      onRespond: (_, response) async => responses.add(response),
      typing: AgentChatTypingClock(),
    ),
  ),
);

void main() {
  testWidgets('the dock shows a masked secret card that saves the value', (
    tester,
  ) async {
    final responses = <AgentChatResponse>[];
    await tester.pumpWidget(_dock(responses));
    expect(find.text('Deploy token'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.decoration?.hintText, 'ghp_...');

    await tester.enterText(find.byType(TextField), _value);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save Secret'));
    await tester.pump();
    final response = responses.single as AgentChatSecretResponse;
    expect(response.value == _value, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('declining sends no value', (tester) async {
    final responses = <AgentChatResponse>[];
    await tester.pumpWidget(_dock(responses));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Decline'));
    await tester.pump();
    expect((responses.single as AgentChatSecretResponse).value, isNull);
  });
}
