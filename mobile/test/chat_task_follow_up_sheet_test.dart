import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_follow_up_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ValueKey<String> _send = ValueKey<String>('chatTaskFollowUpSend');

/// Opens Send Follow-Up on a phone of [size] and returns what it answered.
Future<List<String?>> _openSheet(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboard = 0,
  double homeIndicator = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.view.padding = FakeViewPadding(top: 47, bottom: homeIndicator);
  tester.view.viewPadding = FakeViewPadding(top: 47, bottom: homeIndicator);
  addTearDown(tester.view.reset);
  final answers = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraMobileDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                answers.add(await showChatTaskFollowUpSheet(context)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return answers;
}

void main() {
  testWidgets('Send Follow-Up clears the home indicator', (tester) async {
    await _openSheet(tester, homeIndicator: 34);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(_send)).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 34),
    );
  });

  testWidgets('a short phone at 200% text scrolls to Send over the keys', (
    tester,
  ) async {
    final answers = await _openSheet(
      tester,
      size: const Size(320, 568),
      textScale: 2,
      keyboard: 260,
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('chatTaskFollowUpMessage')),
        matching: find.byType(TextField),
      ),
      '  Add the tests too  ',
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(_send),
      48,
      scrollable: find
          .ancestor(of: find.byKey(_send), matching: find.byType(Scrollable))
          .first,
    );
    expect(
      tester.getRect(find.byKey(_send)).bottom,
      lessThanOrEqualTo(
        tester.view.physicalSize.height - tester.view.viewInsets.bottom,
      ),
    );
    await tester.tap(find.byKey(_send));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(answers, <String?>['Add the tests too']);
  });
}
