import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'support/fake_terminal_client.dart';

void main() {
  testWidgets(
    'Refresh control remounts the view and preserves terminal state',
    (tester) async {
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      await _pumpTab(tester, client);
      final before = _terminalOf(tester);
      final viewStateBefore = tester.state<TerminalViewState>(
        find.byType(TerminalView),
      );
      final viewBefore = tester.widget<TerminalView>(find.byType(TerminalView));
      final controller = viewBefore.controller!;
      final scrollController = viewBefore.scrollController!;
      final focusNode = viewBefore.focusNode!;
      controller.setSelection(
        before.buffer.createAnchor(0, 0),
        before.buffer.createAnchor(1, 0),
      );
      focusNode.requestFocus();
      await tester.pump();
      final callsBefore = List<String>.of(client.calls);
      final terminalRect = tester.getRect(find.byType(TerminalView));
      final refreshRect = tester.getRect(find.byTooltip('Refresh Terminal'));
      expect(
        refreshRect.top,
        closeTo(terminalRect.top + AleraTokens.spaceXs, 0.01),
      );
      expect(
        refreshRect.right,
        closeTo(terminalRect.right - AleraTokens.spaceXs, 0.01),
      );

      await tester.tap(find.byTooltip('Refresh Terminal'));
      await tester.pump();

      expect(find.byTooltip('Refreshing Terminal'), findsOneWidget);
      expect(
        tester.state<TerminalViewState>(find.byType(TerminalView)),
        isNot(same(viewStateBefore)),
      );

      await tester.pumpAndSettle();

      expect(_terminalOf(tester), same(before));
      final viewAfter = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(viewAfter.controller, same(controller));
      expect(viewAfter.scrollController, same(scrollController));
      expect(viewAfter.focusNode, same(focusNode));
      expect(controller.selection, isNotNull);
      expect(focusNode.hasFocus, isTrue);
      expect(client.calls, callsBefore);
      expect(client.writes, isEmpty);
      expect(client.calls, isNot(contains('restart tab-1')));
      expect(find.byTooltip('Refresh Terminal'), findsOneWidget);
    },
  );

  testWidgets('Refresh control is safe after the connection is lost', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    await client.dispose();
    await tester.pumpAndSettle();
    final callsBefore = List<String>.of(client.calls);

    await tester.tap(find.byTooltip('Refresh Terminal'));
    await tester.pump();

    expect(find.text('Terminal unavailable'), findsOneWidget);
    expect(client.calls, callsBefore);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('Paste quick action writes clipboard text without Enter', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': 'first\nsecond'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);

    await tester.tap(find.byTooltip('Paste Clipboard'));
    await tester.pumpAndSettle();

    expect(client.writes.single, utf8.encode('first\nsecond'));
    expect(
      client.calls,
      contains('write session-tab-1 12 paste=true enter=false'),
    );
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
    expect(find.text('Terminal output stopped'), findsNothing);

    await client.dispose();
    await tester.pumpAndSettle();

    expect(find.text('Terminal unavailable'), findsOneWidget);
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
