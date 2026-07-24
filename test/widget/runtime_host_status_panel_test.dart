import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/presentation/runtime_host_status_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chip shows a v-prefixed version under a click cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapChip(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.1.0',
          runtimeHostVersion: '0.1.0',
        ),
      ),
    );

    expect(find.text('Runtime v0.1.0'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(RuntimeHostStatusChip)));
    await tester.pumpAndSettle();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('panel shows v-prefixed versions and no lifecycle settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.2.0',
          runtimeHostVersion: '0.1.0',
          runtimeHostCommit: '1234567',
        ),
      ),
    );

    expect(find.text('v0.1.0'), findsOneWidget);
    expect(find.text('v0.2.0'), findsOneWidget);
    expect(find.text('0.1.0'), findsNothing);
    expect(find.text('Host Commit'), findsNothing);
    expect(find.text('1234567'), findsNothing);
    expect(find.text('Stop Runtime When App Quits'), findsNothing);
    expect(find.text('Empty Host Shutdown'), findsNothing);
    expect(find.text('Detached Session Shutdown'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Running')).style?.color,
      AleraTokens.success,
    );
  });

  testWidgets('panel renders a dash when no host version is reported', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(running: false, bundledVersion: ''),
      ),
    );

    expect(find.text('-'), findsNWidgets(2));
    expect(find.text('Start'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Stopped')).style?.color,
      isNot(AleraTokens.success),
    );
  });

  testWidgets('actions sit at the end of the panel', (tester) async {
    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.1.0',
          runtimeHostVersion: '0.1.0',
        ),
      ),
    );

    final panelRight = tester
        .getRect(find.byType(RuntimeHostStatusPanel))
        .right;
    expect(
      tester.getRect(find.widgetWithText(OutlinedButton, 'Stop')).right,
      // Panel padding plus the 1px border.
      closeTo(panelRight - AleraTokens.space12, 1.5),
    );
    expect(
      tester.getCenter(find.widgetWithText(OutlinedButton, 'Refresh')).dx,
      lessThan(
        tester.getCenter(find.widgetWithText(OutlinedButton, 'Stop')).dx,
      ),
    );
  });

  testWidgets('Stop turns destructive while sessions or agents are attached', (
    tester,
  ) async {
    Color? stopForeground() {
      final style = tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Stop'))
          .style;
      return style?.foregroundColor?.resolve(<WidgetState>{});
    }

    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.1.0',
          runtimeHostVersion: '0.1.0',
        ),
      ),
    );
    expect(stopForeground(), isNot(AleraTokens.error));

    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.1.0',
          runtimeHostVersion: '0.1.0',
          activeSessions: 2,
        ),
      ),
    );
    expect(stopForeground(), AleraTokens.error);

    await tester.pumpWidget(
      _wrapPanel(
        const RuntimeHostStatusSnapshot(
          running: true,
          bundledVersion: '0.1.0',
          runtimeHostVersion: '0.1.0',
          activeAgents: 1,
        ),
      ),
    );
    expect(stopForeground(), AleraTokens.error);
  });
}

Widget _wrapChip(RuntimeHostStatusSnapshot snapshot) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: RuntimeHostStatusChip(
          snapshot: snapshot,
          loading: false,
          onPressed: () {},
        ),
      ),
    ),
  );
}

Widget _wrapPanel(RuntimeHostStatusSnapshot snapshot) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomRight,
        child: RuntimeHostStatusPanel(
          snapshot: snapshot,
          loading: false,
          onRefresh: () {},
          onStart: () {},
          onStop: () {},
          onUpdate: () {},
        ),
      ),
    ),
  );
}
