import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'command_terminal_test_doubles.dart';

const _request = CommandTerminalRequest(
  title: 'Update Alera',
  command: 'sudo apt-get install --only-upgrade alera',
  description: 'The update runs here. Answer any prompt in the terminal.',
);

Future<void> _pumpDialog(
  WidgetTester tester,
  FakeCommandTerminalSession session,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: CommandTerminalDialog(request: _request, session: session),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the command and starts the session', (tester) async {
    final session = FakeCommandTerminalSession();
    await _pumpDialog(tester, session);

    expect(find.text('Update Alera'), findsOneWidget);
    expect(find.text(_request.command), findsOneWidget);
    expect(find.text(_request.description!), findsOneWidget);
    expect(session.ensureStartedCallCount, 1);
  });

  testWidgets('copies the command', (tester) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            clipboardText = arguments['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pumpDialog(tester, FakeCommandTerminalSession());
    await tester.tap(find.byTooltip('Copy Command'));
    await tester.pump();

    expect(clipboardText, _request.command);
  });

  testWidgets('closing a live shell asks before killing it', (tester) async {
    final session = FakeCommandTerminalSession();
    await _pumpDialog(tester, session);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Stop Running Command?'), findsOneWidget);

    // Cancelling leaves the command alone and the dialog on screen.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Stop Running Command?'), findsNothing);
    expect(find.text(_request.command), findsOneWidget);
  });

  testWidgets('confirming the stop closes the dialog', (tester) async {
    final session = FakeCommandTerminalSession();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => CommandTerminalDialog(
                    request: _request,
                    session: session,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop And Close'));
    await tester.pumpAndSettle();

    expect(find.text(_request.command), findsNothing);
  });

  testWidgets('a shell the user already exited closes without asking', (
    tester,
  ) async {
    final session = FakeCommandTerminalSession(running: false);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => CommandTerminalDialog(
                    request: _request,
                    session: session,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Stop Running Command?'), findsNothing);
    expect(find.text(_request.command), findsNothing);
  });
}
