import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_viewport_pulse.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2/xterm.dart';

import 'support/fake_terminal_client.dart';
import 'support/memory_accessory_layout_repository.dart';

void main() {
  testWidgets(
    'Portrait terminal viewport fits the chrome above the compose stack',
    (tester) async {
      await _setPhoneSurface(tester, AleraTokens.previewPhoneSize);
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      await _pumpTab(tester, client);

      final body = tester.getRect(find.byType(Scaffold));
      final terminalRect = tester.getRect(find.byType(TerminalView));
      final accessoryRect = tester.getRect(find.byType(TerminalAccessoryBar));
      final composeRect = tester.getRect(find.byType(TerminalComposeBar));
      final terminal = _terminalOf(tester);

      expect(terminalRect.left, greaterThanOrEqualTo(body.left));
      expect(terminalRect.right, lessThanOrEqualTo(body.right + 0.5));
      expect(terminalRect.bottom, lessThanOrEqualTo(accessoryRect.top + 0.5));
      expect(accessoryRect.bottom, lessThanOrEqualTo(composeRect.top + 0.5));
      expect(composeRect.bottom, lessThanOrEqualTo(body.bottom + 0.5));
      expect(terminal.viewWidth, greaterThan(20));
      expect(terminal.viewHeight, greaterThan(10));
      expect(
        _resizeCalls(client).first,
        'resize session-tab-1 ${terminal.viewWidth} ${terminal.viewHeight}',
      );
    },
  );

  testWidgets('Scrolling a hidden-cursor TUI does not walk the cell buffer', (
    tester,
  ) async {
    await _setPhoneSurface(tester, AleraTokens.previewPhoneSize);
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);

    final terminal = _terminalOf(tester);
    terminal.write('\x1b[?25l');
    for (var line = 0; line < 60; line++) {
      terminal.write('history-$line\r\n');
    }
    terminal.write('LIVE');
    await tester.pump();

    final scroll = tester
        .widget<TerminalView>(find.byType(TerminalView))
        .scrollController!;
    final offsetBefore = scroll.offset;
    final writesBefore = client.writes.length;

    await tester.drag(find.byType(TerminalView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(scroll.offset, offsetBefore);
    expect(client.writes.length, greaterThan(writesBefore));
    expect(
      utf8.decode(
        client.writes.sublist(writesBefore).expand((bytes) => bytes).toList(),
      ),
      contains('\x1B[B'),
    );
    expect(terminal.buffer.getText(), contains('LIVE'));
  });

  testWidgets('A settled orientation change pulses the new viewport', (
    tester,
  ) async {
    await _setPhoneSurface(tester, AleraTokens.previewPhoneSize);
    final client = FakeTerminalClient()
      ..tabs = <WorkspaceTabSummary>[fakeTab(id: 'tab-1', title: 'Terminal 1')];
    await _pumpTab(tester, client);
    final portrait = _terminalOf(tester);
    final portraitCols = portrait.viewWidth;

    await _setPhoneSurface(tester, const Size(844, 390));
    await tester.pumpAndSettle();
    await tester.pump(terminalViewportPulseDebounce);

    final landscape = _terminalOf(tester);
    expect(landscape.viewWidth, isNot(portraitCols));
    final pulse = terminalViewportPulseSize(
      landscape.viewWidth,
      landscape.viewHeight,
    );
    final resizes = _resizeCalls(client);
    expect(
      resizes.last,
      'resize session-tab-1 ${landscape.viewWidth} ${landscape.viewHeight}',
    );
    expect(
      resizes,
      contains('resize session-tab-1 ${pulse.$1} ${landscape.viewHeight}'),
    );
  });

  testWidgets(
    'PTY size matches the phone viewport after chrome and safe areas',
    (tester) async {
      await _setPhoneSurface(
        tester,
        AleraTokens.previewPhoneSize,
        padding: const FakeViewPadding(top: 47, bottom: 34),
      );
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            terminalClientProvider('host-1')
                .overrideWith((ref) async => client),
            workspaceClientProvider('host-1')
                .overrideWith((ref) async => client),
            accessoryLayoutRepositoryProvider.overrideWithValue(
              MemoryAccessoryLayoutRepository(),
            ),
          ],
          child: const MaterialApp(
            home: WorkspaceTabsScreen(
              hostId: 'host-1',
              workspace: WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project-1',
                name: 'Workspace',
                path: '/repo',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminal = _terminalOf(tester);
      final viewState = tester.state<TerminalViewState>(
        find.byType(TerminalView),
      );
      final render = viewState.renderTerminal;
      final cell = render.cellSize;
      final innerWidth = render.size.width;
      final innerHeight = render.size.height;
      final expectedCols = innerWidth ~/ cell.width;
      final expectedRows = innerHeight ~/ cell.height;

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(TerminalAccessoryBar), findsOneWidget);
      expect(find.byType(TerminalComposeBar), findsOneWidget);
      expect(terminal.viewWidth, expectedCols);
      expect(terminal.viewHeight, expectedRows);
      expect(terminal.viewWidth, isNot(80));
      expect(terminal.viewHeight, isNot(24));
      expect(innerWidth - expectedCols * cell.width, lessThan(cell.width));
      expect(innerHeight - expectedRows * cell.height, lessThan(cell.height));
      expect(
        _resizeCalls(client).first,
        'resize session-tab-1 $expectedCols $expectedRows',
      );
      final composeBottom = tester
          .getRect(find.byType(TerminalComposeBar))
          .bottom;
      final screen = tester.getRect(find.byType(MaterialApp));
      expect(composeBottom, lessThanOrEqualTo(screen.bottom - 34 + 0.5));
    },
  );

  testWidgets(
    'Scrolling restored history keeps upper rows intact at phone width',
    (tester) async {
      await _setPhoneSurface(tester, AleraTokens.previewPhoneSize);
      final history = <String>[
        for (var line = 0; line < 80; line++)
          'ROW-${line.toString().padLeft(2, '0')}',
      ];
      final client = FakeTerminalClient()
        ..tabs = <WorkspaceTabSummary>[
          fakeTab(id: 'tab-1', title: 'Terminal 1'),
        ]
        ..attachmentSnapshot = utf8.encode('${history.join('\r\n')}\r\nLIVE')
        ..attachmentSnapshotCols = 200
        ..attachmentSnapshotRows = 50;
      await _pumpTab(tester, client);

      final terminal = _terminalOf(tester);
      expect(terminal.viewWidth, lessThan(200));
      expect(_resizeCalls(client).first, isNot(contains(' 200 50')));

      final scroll = tester
          .widget<TerminalView>(find.byType(TerminalView))
          .scrollController!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pump();

      final rows = <String>[
        for (var index = 0; index < terminal.buffer.lines.length; index++)
          terminal.buffer.lines[index].toString().trim(),
      ].where((line) => line.startsWith('ROW-')).toList();
      expect(rows.first, 'ROW-00');
      expect(rows.last, 'ROW-79');
      expect(rows, history);
      expect(terminal.buffer.getText(), contains('LIVE'));
      expect(rows.where((line) => line.contains('ROW-00')).length, 1);
    },
  );
}

Terminal _terminalOf(WidgetTester tester) {
  return tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
}

List<String> _resizeCalls(FakeTerminalClient client) {
  return client.calls.where((call) => call.startsWith('resize ')).toList();
}

Future<void> _setPhoneSurface(
  WidgetTester tester,
  Size size, {
  FakeViewPadding? padding,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  if (padding != null) {
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
  }
  addTearDown(() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _pumpTab(WidgetTester tester, FakeTerminalClient client) async {
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
  await tester.pumpAndSettle();
}
