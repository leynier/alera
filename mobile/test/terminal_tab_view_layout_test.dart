import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_viewport_pulse.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_accessory_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_compose_bar.dart';
import 'package:alera_mobile/src/features/terminal/presentation/terminal_tab_view.dart';
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
}

Terminal _terminalOf(WidgetTester tester) {
  return tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
}

List<String> _resizeCalls(FakeTerminalClient client) {
  return client.calls.where((call) => call.startsWith('resize ')).toList();
}

Future<void> _setPhoneSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
