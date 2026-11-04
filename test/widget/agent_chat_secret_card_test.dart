import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_secret_card.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _value = 'synthetic-test-value';

final _request = AgentChatRequest.fromJson(<String, Object?>{
  'requestId': 'request-1',
  'kind': 'secret_input',
  'title': 'Deploy token',
  'detail': 'To deploy the preview.',
  'masked': true,
  'questions': <Object?>[
    <String, Object?>{'id': 'value', 'placeholder': 'ghp_...'},
  ],
});

Widget _host(ValueChanged<String?> onProvide, {bool enabled = true}) =>
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: AgentChatSecretCard(
          request: _request,
          responding: false,
          enabled: enabled,
          onProvide: onProvide,
        ),
      ),
    );

void main() {
  testWidgets('saves a masked value once and clears the field', (tester) async {
    final provided = <String?>[];
    await tester.pumpWidget(_host(provided.add));
    expect(find.text('Deploy token'), findsOneWidget);
    expect(find.text('To deploy the preview.'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.decoration?.hintText, 'ghp_...');
    final save = find.widgetWithText(FilledButton, 'Save Secret');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.enterText(find.byType(TextField), _value);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(provided.length, 1);
    expect(provided.single == _value, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
  });

  testWidgets('declines without a value', (tester) async {
    final provided = <String?>[];
    await tester.pumpWidget(_host(provided.add));
    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pump();
    expect(provided, <String?>[null]);
  });

  testWidgets('offers nothing while the chat is offline', (tester) async {
    await tester.pumpWidget(_host((_) {}, enabled: false));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Decline'))
          .onPressed,
      isNull,
    );
  });
}
