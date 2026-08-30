part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceRetentionTests() {
  for (final replaceWhileHidden in [false, true]) {
    testWidgets(
      'retained terminal survives budget pressure and '
      '${replaceWhileHidden ? 'releases a replaced session' : 'resumes output'}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        final factory = _FakeTerminalPtySessionFactory();
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: _testShellLaunches,
        );
        final first = runtime.sessionFor(workspace: _workspace(), tab: _tab());
        final selected = ValueNotifier(first);
        final visible = ValueNotifier(true);
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                agentCanvasesProvider(first.workspaceId)
                    .overrideWith((ref) => Stream.value(const [])),
                settingsControllerProvider.overrideWith(
                  () => _FakeSettingsController(AleraSettings.defaults),
                ),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ValueListenableBuilder(
                    valueListenable: visible,
                    builder: (context, show, child) => Visibility(
                      visible: show,
                      maintainState: true,
                      child: child!,
                    ),
                    child: ValueListenableBuilder(
                      valueListenable: selected,
                      builder: (context, session, _) =>
                          TerminalSurface(session: session),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
          final firstPty = factory.sessions.single;
          _fillRetainedTerminalBuffer(first);
          runtime.updateSettings(
            TerminalSettings.defaults.copyWith(bufferBudgetMegabytes: 1),
          );
          final surface = tester.state(find.byType(TerminalSurface));

          visible.value = false;
          await tester.pump();
          expect(first.isVisible, isFalse);
          expect(firstPty.outputPausedCalls.last, isTrue);
          expect(firstPty.disposed, isFalse);
          expect(runtime.peekSession(first.tabId), same(first));
          expect(tester.takeException(), isNull);

          if (replaceWhileHidden) {
            final replacement = runtime.sessionFor(
              workspace: _workspace(),
              tab: _tab(id: 'tab-2'),
            );
            selected.value = replacement;
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            _fillRetainedTerminalBuffer(replacement);
            expect(runtime.peekSession(first.tabId), isNull);
            await _settleRetainedPtyDisposal(tester, firstPty);
            expect(firstPty.disposed, isTrue);
            expect(firstPty.terminated, isFalse);
          } else {
            firstPty.emitOutput(utf8.encode('hidden output'));
            await tester.pump(const Duration(seconds: 1));
            expect(pendingTerminalOutputCharsForTesting(first), greaterThan(0));
            expect(terminalOutputFlushScheduledForTesting(first), isFalse);
          }

          visible.value = true;
          await tester.pump();
          await _pumpTerminalOutput(tester);
          expect(tester.state(find.byType(TerminalSurface)), same(surface));
          expect(selected.value.isVisible, isTrue);
          expect(
            runtime.peekSession(selected.value.tabId),
            same(selected.value),
          );
          expect(factory.sessions.last.outputPausedCalls.last, isFalse);
          if (!replaceWhileHidden) {
            expect(
              terminalBufferTextForTesting(first).contains('hidden output'),
              isTrue,
            );
            expect(factory.sessions, hasLength(1));
          }
          expect(tester.takeException(), isNull);

          visible.value = false;
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(runtime.peekSession(selected.value.tabId), isNull);
          await _settleRetainedPtyDisposal(tester, factory.sessions.last);
          expect(factory.sessions.last.disposed, isTrue);
          expect(factory.sessions.every((pty) => !pty.terminated), isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          runtime.dispose();
          selected.dispose();
          visible.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}

void _fillRetainedTerminalBuffer(TerminalSessionHandle session) {
  writeTerminalOutputForTesting(session, '${'x' * 64}\r\n' * 4000);
  expect(session.bufferUsage.bytes, greaterThan(1024 * 1024));
}

Future<void> _settleRetainedPtyDisposal(
  WidgetTester tester,
  _FakeTerminalPtySession pty,
) async {
  // Stream cancellation crosses the real event queue before detaching the PTY.
  for (var attempt = 0; attempt < 10 && !pty.disposed; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}
