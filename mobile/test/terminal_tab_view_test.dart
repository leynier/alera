import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets('Live output keeps the same emulator', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    final before = _terminalOf(tester);

    client.emitOutput(
      'session-tab-1',
      Uint8List.fromList(utf8.encode('hello')),
    );
    await tester.pumpAndSettle();

    expect(_terminalOf(tester), same(before));
  });

  testWidgets('A resync snapshot replaces the emulator', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    final before = _terminalOf(tester);

    // The host could not place this client in the stream any more, so it
    // answered with a snapshot. Appending it would duplicate the scrollback.
    client.emitOutput(
      'session-tab-1',
      Uint8List.fromList(utf8.encode('restored')),
      replacesScrollback: true,
    );
    await tester.pumpAndSettle();

    expect(_terminalOf(tester), isNot(same(before)));
  });

  testWidgets('A dead connection offers explicit recovery', (tester) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    expect(find.text('Terminal Output Stopped'), findsNothing);

    await client.dispose();
    await tester.pumpAndSettle();

    expect(find.text('Terminal Unavailable'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Restart Terminal'), findsOneWidget);
  });

  testWidgets('Restart requires confirmation before replacing the process', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    await client.dispose();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restart Terminal'));
    await tester.pumpAndSettle();

    expect(find.text('Restart Terminal?'), findsOneWidget);
    expect(client.calls, isNot(contains('restart tab-1')));

    await tester.tap(
      find.widgetWithText(FilledButton, 'Restart Terminal').last,
    );
    await tester.pumpAndSettle();

    expect(client.calls, contains('restart tab-1'));
  });
}

Terminal _terminalOf(WidgetTester tester) {
  return tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
}

Future<void> _pumpTab(WidgetTester tester, FakeTerminalClient client) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: TerminalTabView(hostId: 'host-1', tabId: 'tab-1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
