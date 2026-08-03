part of 'terminal_surface_test.dart';

void _registerTerminalSurfaceComposerSubmitTests() {
  testWidgets('runtime prompt submission uses deferred enter when supported', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final factory = _FakeDeferredEnterTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(
        ptySessionFactory: factory,
        shellLaunchesBuilder: _testShellLaunches,
      );
      addTearDown(runtime.dispose);
      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();
      final submitted = await session.submitText('Review this change');

      expect(submitted, isTrue);
      final pty = factory.sessions.single;
      expect(pty.writes, isEmpty);
      expect(pty.deferredEnterWrites.map(utf8.decode).toList(), <String>[
        'Review this change',
      ]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(pty.writes, isEmpty);
      expect(pty.deferredEnterWrites.map(utf8.decode).toList(), <String>[
        'Review this change',
      ]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'fallback submit drops Enter when the session is disposed early',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final factory = _FakeTerminalPtySessionFactory();
        final runtime = XtermTerminalRuntime(
          ptySessionFactory: factory,
          shellLaunchesBuilder: _testShellLaunches,
        );
        final session = runtime.sessionFor(
          workspace: _workspace(),
          tab: _tab(),
        );

        await session.ensureStarted();
        final submitted = await session.submitText('Review this change');
        expect(submitted, isTrue);
        expect(
          factory.sessions.single.writes.map(utf8.decode).toList(),
          <String>['Review this change'],
        );

        // Dispose the runtime (and its session) before the local fallback timer
        // fires so a closed PTY never receives a stray CR.
        runtime.dispose();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          factory.sessions.single.writes.map(utf8.decode).toList(),
          <String>['Review this change'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}

class _FakeDeferredEnterTerminalPtySessionFactory
    implements TerminalPtySessionFactory {
  final List<_FakeDeferredEnterTerminalPtySession> sessions =
      <_FakeDeferredEnterTerminalPtySession>[];

  @override
  TerminalPtySession create({
    required String sessionId,
    required String workspaceId,
    required String tabId,
  }) {
    final session = _FakeDeferredEnterTerminalPtySession();
    sessions.add(session);
    return session;
  }
}

class _FakeDeferredEnterTerminalPtySession
    implements DeferredEnterTerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  final List<List<int>> writes = <List<int>>[];
  final List<List<int>> deferredEnterWrites = <List<int>>[];
  bool disposed = false;
  bool terminated = false;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  bool get startedNewProcess => true;

  @override
  bool get supportsDeferredEnter => true;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required String workingDirectory,
    required int cols,
    required int rows,
    Future<void> Function()? onProcessCreated,
  }) async {
    await onProcessCreated?.call();
  }

  @override
  bool writeBytes(List<int> bytes) {
    writes.add(List<int>.from(bytes));
    return bytes.isNotEmpty;
  }

  @override
  bool writeBytesWithDeferredEnter(List<int> bytes) {
    deferredEnterWrites.add(List<int>.from(bytes));
    return true;
  }

  @override
  Future<bool> writeBytesAndWait(List<int> bytes) async => writeBytes(bytes);

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {}

  @override
  Future<void> refreshViewport(
    int cols,
    int rows,
    int cellWidthPx,
    int cellHeightPx,
  ) async {}

  @override
  Future<void> setOutputPaused(bool paused) async {}

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    unawaited(_events.close());
  }

  @override
  void terminate() {
    terminated = true;
    dispose();
  }
}
