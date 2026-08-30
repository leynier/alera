import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/keep_alive/presentation/keep_alive_status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chip uses the click cursor and muted color when off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const KeepAliveStatusChip(
          snapshot: .inactive(),
          enabled: false,
          onPressed: _noop,
        ),
      ),
    );

    expect(find.text('Keep Alive'), findsOneWidget);
    expect(_labelColor(tester), AleraTokens.foregroundMuted);

    final mouse = await tester.createGesture(kind: .mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: .zero);
    await mouse.moveTo(tester.getCenter(find.byType(KeepAliveStatusChip)));
    await tester.pumpAndSettle();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('chip uses the success color when keep-alive is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const KeepAliveStatusChip(
          snapshot: .active(),
          enabled: true,
          onPressed: _noop,
        ),
      ),
    );

    expect(_labelColor(tester), AleraTokens.success);
  });

  testWidgets('chip uses the warning color when the lock failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const KeepAliveStatusChip(
          snapshot: .inactive(error: 'not supported'),
          enabled: false,
          onPressed: _noop,
        ),
      ),
    );

    expect(_labelColor(tester), AleraTokens.warning);
  });

  testWidgets('chip invokes onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        KeepAliveStatusChip(
          snapshot: const .inactive(),
          enabled: false,
          onPressed: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(KeepAliveStatusChip));
    expect(taps, 1);
  });
}

void _noop() {}

Color? _labelColor(WidgetTester tester) {
  return tester.widget<Text>(find.text('Keep Alive')).style?.color;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(alignment: Alignment.bottomRight, child: child),
    ),
  );
}
