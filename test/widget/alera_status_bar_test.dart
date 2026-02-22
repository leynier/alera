import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpStatusBar(
  WidgetTester tester, {
  required bool canCopyRawLog,
  required VoidCallback onCopyRawLog,
  required VoidCallback onToggleRawLog,
  bool rawLogExpanded = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AleraStatusBar(
          state: const SessionState(selectedWorkspacePath: '/repo'),
          rawLogExpanded: rawLogExpanded,
          onToggleRawLog: onToggleRawLog,
          onCopyRawLog: onCopyRawLog,
          canCopyRawLog: canCopyRawLog,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('copy raw log button is tappable when enabled', (tester) async {
    var copyCalls = 0;
    await _pumpStatusBar(
      tester,
      canCopyRawLog: true,
      onCopyRawLog: () => copyCalls += 1,
      onToggleRawLog: () {},
    );

    await tester.tap(find.byKey(const ValueKey<String>('copy-raw-log-button')));
    await tester.pump();

    expect(copyCalls, 1);
  });

  testWidgets('copy raw log button does not fire when disabled', (
    tester,
  ) async {
    var copyCalls = 0;
    await _pumpStatusBar(
      tester,
      canCopyRawLog: false,
      onCopyRawLog: () => copyCalls += 1,
      onToggleRawLog: () {},
    );

    await tester.tap(find.byKey(const ValueKey<String>('copy-raw-log-button')));
    await tester.pump();

    expect(copyCalls, 0);
  });

  testWidgets('raw log toggle still fires callback', (tester) async {
    var toggleCalls = 0;
    await _pumpStatusBar(
      tester,
      canCopyRawLog: true,
      onCopyRawLog: () {},
      onToggleRawLog: () => toggleCalls += 1,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('toggle-raw-log-button')),
    );
    await tester.pump();

    expect(toggleCalls, 1);
  });
}
