import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_session_controller.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:xterm/xterm.dart';

import 'support/fake_terminal_client.dart';
import 'support/memory_accessory_layout_repository.dart';

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

  testWidgets('Raw restore bytes are released after reaching the emulator', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = Uint8List.fromList(utf8.encode('restored'));

    await _pumpTab(tester, client);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerminalTabView)),
    );
    final session = container
        .read(terminalSessionControllerProvider('host-1', 'tab-1'))
        .requireValue;
    expect(session.retainedSnapshotBytes, 0);
  });

  testWidgets('Restoring a tab holds the view back until its history is in', (
    tester,
  ) async {
    // Shown, this replay reads as the terminal scrolling itself from the top
    // of history down to the live screen every time a tab is opened.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      // Past the per-frame budget, so the restore spans frames like a real
      // scrollback does rather than landing in the first one.
      ..attachmentSnapshot = utf8.encode('a' * (200 * 1024));
    await _pumpTab(tester, client, settle: false);

    expect(find.text('Restoring terminal'), findsOneWidget);
    expect(find.byType(TerminalView), findsNothing);
    final first = _restoreFraction(tester);

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Restoring terminal'), findsOneWidget);
    expect(_restoreFraction(tester), greaterThan(first));

    await _drainRestore(tester);

    expect(find.byType(TerminalView), findsOneWidget);
    expect(_terminalOf(tester).buffer.lines.length, greaterThan(0));
  });

  testWidgets('Restored history is replayed at the size that produced it', (
    tester,
  ) async {
    // The snapshot is the raw PTY stream, so it only reconstructs its screen
    // at the geometry it was written at. Parsing it at the phone's much
    // narrower width put every absolute cursor move and hard wrap in the wrong
    // column, which is what made the scrollback unreadable while the live
    // screen below it looked fine.
    //
    // Column 180 is past any phone's width, so where TAIL lands says which
    // width parsed it without the test having to know the phone's own.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = utf8.encode('\x1b[1;180HTAIL')
      ..attachmentSnapshotCols = 200
      ..attachmentSnapshotRows = 50;

    await _pumpTab(tester, client);

    final terminal = _terminalOf(tester);
    expect(terminal.viewWidth, lessThan(180));
    // Rows are padded back out so the reflowed buffer reads as the one long
    // logical line it is, and the column TAIL sits in survives the wrapping.
    final joined = <String>[
      for (var row = 0; row < terminal.buffer.lines.length; row++)
        terminal.buffer.lines[row].toString().padRight(terminal.viewWidth),
    ].join();
    // Parsed at any narrower width, the cursor move clamps to that width and
    // TAIL lands there instead of at the column the host wrote it at.
    expect(joined.indexOf('TAIL'), 179);
    // The phone's own size is claimed once, and only once it is real.
    expect(
      client.calls.where((call) => call.startsWith('resize ')),
      hasLength(1),
    );
  });

  testWidgets('Restored history survives the resize with the cursor hidden', (
    tester,
  ) async {
    // An agent TUI leaves the cursor hidden for as long as it runs, and the
    // emulator reads that as a full-screen program that will redraw itself: it
    // truncates every line to the new width instead of reflowing. True of the
    // live screen, false of the history above it, which nothing redraws.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = utf8.encode('\x1b[?25l\x1b[1;180HTAIL')
      ..attachmentSnapshotCols = 200
      ..attachmentSnapshotRows = 50;

    await _pumpTab(tester, client);

    final terminal = _terminalOf(tester);
    final joined = <String>[
      for (var row = 0; row < terminal.buffer.lines.length; row++)
        terminal.buffer.lines[row].toString().padRight(terminal.viewWidth),
    ].join();
    expect(joined.indexOf('TAIL'), 179);
  });

  testWidgets('Restored history is kept past what fits at the host width', (
    tester,
  ) async {
    // Reflowing to the phone's width turns one host line into several, so a
    // budget sized for the host width keeps a fraction of the history it was
    // meant to. The scrollback the desktop shows takes roughly four times the
    // lines here, at a quarter of the width.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = utf8.encode(
        <String>[
          for (var line = 0; line < 8000; line++) 'line-$line',
        ].join('\r\n'),
      )
      ..attachmentSnapshotCols = 200
      ..attachmentSnapshotRows = 50;

    await _pumpTab(tester, client, settle: false);
    await _drainRestore(tester);

    final terminal = _terminalOf(tester);
    final first = terminal.buffer.lines[0].toString().trim();
    expect(first, 'line-0', reason: 'the oldest line was dropped');
  });

  testWidgets('A host that states no snapshot size replays as it always did', (
    tester,
  ) async {
    // Older hosts omit the field, and an attach against one has to keep
    // working rather than resize the emulator to nothing.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')]
      ..attachmentSnapshot = utf8.encode('restored');

    await _pumpTab(tester, client);

    expect(_terminalOf(tester).buffer.lines[0].toString(), 'restored');
  });

  testWidgets('A tab with no history to restore is never covered', (
    tester,
  ) async {
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];

    await _pumpTab(tester, client, settle: false);

    expect(find.text('Restoring terminal'), findsNothing);
  });

  testWidgets('The first attach claims no viewport until one is measured', (
    tester,
  ) async {
    // The host resizes the live PTY to whatever viewport a phone claims, so a
    // placeholder here resized the session to 80x24 and then again to the real
    // size a layout later, redrawing a full-screen agent at both.
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];

    await _pumpTab(tester, client);

    expect(client.attachments.single.cols, isNull);
    expect(client.attachments.single.rows, isNull);
    // The measured size still reaches the host, just once and only when real.
    final resize = client.calls.firstWhere(
      (call) => call.startsWith('resize '),
    );
    expect(resize, isNot(endsWith(' 80 24')));
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

    // Paste is an ordinary quick key now, found by its key rather than the
    // tooltip the old fixed rail carried.
    await tester.tap(
      find.byKey(const ValueKey<String>('terminal-accessory-paste')),
    );
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

/// Pumps until the restore has drained and the view is back.
///
/// The batcher paces itself with a timer between frames, and while the view is
/// held back nothing else schedules one, so `pumpAndSettle` returns before the
/// timer is due. A real frame loop keeps running regardless.
Future<void> _drainRestore(WidgetTester tester) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('Restoring terminal').evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('the restore never drained');
}

double _restoreFraction(WidgetTester tester) {
  return tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value ??
      0;
}

Future<void> _pumpTab(
  WidgetTester tester,
  FakeTerminalClient client, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        accessoryLayoutRepositoryProvider.overrideWithValue(
          MemoryAccessoryLayoutRepository(),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: TerminalTabView(
            hostId: 'host-1',
            workspaceId: 'workspace-1',
            tabId: 'tab-1',
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
    return;
  }
  // Settling would drain the whole restore, which is the state under test.
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump();
    final attached =
        find.byType(TerminalView).evaluate().isNotEmpty ||
        find.text('Restoring terminal').evaluate().isNotEmpty;
    if (attached) {
      return;
    }
  }
  fail('the terminal never attached');
}
