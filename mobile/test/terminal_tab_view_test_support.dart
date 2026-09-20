part of 'terminal_tab_view_test.dart';

Terminal _terminalOf(WidgetTester tester) {
  return tester.widget<TerminalView>(find.byType(TerminalView)).terminal;
}

List<String> _resizeCalls(FakeTerminalClient client) {
  return client.calls.where((call) => call.startsWith('resize ')).toList();
}

List<String> _pulsedResizeCalls(String sessionId, int cols, int rows) {
  final pulse = terminalViewportPulseSize(cols, rows);
  return <String>[
    'resize $sessionId $cols $rows',
    'resize $sessionId ${pulse.$1} ${pulse.$2}',
    'resize $sessionId $cols $rows',
  ];
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
  bool allowOsc52Clipboard = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        terminalClientProvider('host-1').overrideWith((ref) async => client),
        workspaceClientProvider('host-1').overrideWith((ref) async => client),
        accessoryLayoutRepositoryProvider.overrideWithValue(
          MemoryAccessoryLayoutRepository(),
        ),
        terminalClipboardSettingsControllerProvider.overrideWith(
          () => _FixedTerminalClipboardSettings(allowOsc52Clipboard),
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

/// Keeps the clipboard opt-in out of SharedPreferences for these tests.
class _FixedTerminalClipboardSettings
    extends TerminalClipboardSettingsController {
  _FixedTerminalClipboardSettings(this.allowed);

  final bool allowed;

  @override
  Future<bool> build() async => allowed;
}
