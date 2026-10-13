import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an action toast runs its action and dismisses itself', (
    tester,
  ) async {
    var opened = 0;
    await _pumpHost(tester);

    AleraToast.publish(
      message: 'Build Mac disconnected. Reconnecting…',
      tone: .warning,
      duration: const Duration(seconds: 5),
      actionLabel: 'Open Host',
      onAction: () => opened++,
    );
    await tester.pump();

    expect(find.text('Open Host'), findsOneWidget);
    await tester.tap(find.text('Open Host'));
    await tester.pump();
    expect(opened, 1);

    await tester.pump(AleraTokens.durationMid);
    expect(find.text('Build Mac disconnected. Reconnecting…'), findsNothing);
  });

  testWidgets('only a card with an action takes pointer input', (tester) async {
    await _pumpHost(tester);

    AleraToast.publish(message: 'Saved', duration: const Duration(seconds: 5));
    AleraToast.publish(
      message: 'Build Mac: Permission denied',
      tone: .error,
      duration: const Duration(seconds: 5),
      actionLabel: 'Open Host',
      onAction: () {},
    );
    await tester.pump();

    IgnorePointer ignoreAbove(String text) => tester.widget<IgnorePointer>(
      find
          .ancestor(of: find.text(text), matching: find.byType(IgnorePointer))
          .first,
    );
    expect(ignoreAbove('Saved').ignoring, isTrue);
    expect(ignoreAbove('Build Mac: Permission denied').ignoring, isFalse);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('a toast without a label shows no action', (tester) async {
    await _pumpHost(tester);

    AleraToast.publish(
      message: 'Saved',
      duration: const Duration(milliseconds: 20),
      actionLabel: '  ',
      onAction: () {},
    );
    await tester.pump();

    expect(find.byType(TextButton), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('clicks pass through the host around an action toast', (
    tester,
  ) async {
    var tappedBehind = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tappedBehind++,
                ),
              ),
              const AleraToastHost(),
            ],
          ),
        ),
      ),
    );

    AleraToast.publish(
      message: 'Build Mac disconnected.',
      duration: const Duration(milliseconds: 20),
      actionLabel: 'Open Host',
      onAction: () {},
    );
    await tester.pump();

    await tester.tapAt(const Offset(20, 20));
    expect(tappedBehind, 1);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });
}

Future<void> _pumpHost(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: const Scaffold(body: AleraToastHost()),
    ),
  );
}
