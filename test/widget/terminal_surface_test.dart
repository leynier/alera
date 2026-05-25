import 'dart:async';

import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/domain/terminal_theme_catalog.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:xterm/xterm.dart' as xterm;

void main() {
  test('working directory launch keeps the shell usable if cd fails', () {
    const launch = GhosttyTerminalShellLaunch(
      label: 'zsh',
      shell: '/bin/zsh',
      arguments: <String>['-l'],
      environment: <String, String>{'TERM': 'xterm-256color'},
      setupCommand: 'echo ready\n',
    );

    final wrapped = launchInWorkingDirectoryForTesting(
      launch,
      "/missing/workspace's path",
    );

    expect(wrapped.shell, '/bin/sh');
    expect(wrapped.arguments, hasLength(2));
    expect(wrapped.arguments.first, '-c');
    expect(
      wrapped.arguments.last,
      "cd '/missing/workspace'\"'\"'s path' || true; exec '/bin/zsh' '-l'",
    );
    expect(wrapped.environment, launch.environment);
    expect(wrapped.setupCommand, launch.setupCommand);
  });

  test('working directory launch preserves Windows command prompt', () {
    const launch = GhosttyTerminalShellLaunch(
      label: 'cmd.exe',
      shell: r'C:\Windows\System32\cmd.exe',
      environment: <String, String>{'TERM': 'xterm-256color'},
    );

    final wrapped = launchInWorkingDirectoryForTesting(
      launch,
      r'C:\Users\alera\workspace',
    );

    expect(wrapped.shell, launch.shell);
    expect(wrapped.arguments, <String>[
      '/d',
      '/s',
      '/k',
      r'cd /d "C:\Users\alera\workspace"',
    ]);
    expect(wrapped.environment, launch.environment);
    expect(wrapped.setupCommand, launch.setupCommand);
  });

  testWidgets('xterm runtime starts with injected PTY on Linux desktop', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final factory = _FakeTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(ptySessionFactory: factory);
      addTearDown(runtime.dispose);
      final exits = <TerminalRuntimeExitEvent>[];
      final exitSub = runtime.exits.listen(exits.add);
      addTearDown(exitSub.cancel);

      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();

      expect(session.errorMessage, isNull);
      expect(session.isRunning, isTrue);
      expect(factory.sessions, hasLength(1));
      expect(factory.sessions.single.startedLaunch, isNotNull);
      expect(factory.sessions.single.startedCols, greaterThan(0));
      expect(factory.sessions.single.startedRows, greaterThan(0));

      factory.sessions.single.emitExit(7);
      factory.sessions.single.emitExit(9);
      await tester.pump();

      expect(session.isRunning, isFalse);
      expect(exits, hasLength(1));
      expect(exits.single.workspaceId, 'ws-1');
      expect(exits.single.tabId, 'tab-1');
      expect(exits.single.exitCode, 7);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('xterm runtime suppresses exits from intentional tab closes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final factory = _FakeTerminalPtySessionFactory();
      final runtime = XtermTerminalRuntime(ptySessionFactory: factory);
      addTearDown(runtime.dispose);
      final exits = <TerminalRuntimeExitEvent>[];
      final exitSub = runtime.exits.listen(exits.add);
      addTearDown(exitSub.cancel);

      final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());

      await session.ensureStarted();
      factory.sessions.single.exitCodeOnDispose = 0;

      runtime.closeTab('tab-1');
      await tester.pump();
      await tester.pump();
      factory.sessions.single.emitExit(0);
      await tester.pump();

      expect(exits, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'changing workspace metadata during build does not notify synchronously',
    (tester) async {
      final runtime = XtermTerminalRuntime();
      addTearDown(runtime.dispose);
      final tab = WorkspaceTabRecord(
        id: 'tab-1',
        workspaceId: 'ws-1',
        title: 'Terminal 1',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      Workspace workspaceWithPath(String path) => Workspace(
        id: 'ws-1',
        projectId: 'p-1',
        name: 'Main',
        branch: 'main',
        path: path,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );

      final pathNotifier = ValueNotifier<String>('/tmp/a');
      addTearDown(pathNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<String>(
              valueListenable: pathNotifier,
              builder: (context, path, _) {
                // sessionFor().sync() runs here, during build.
                final session = runtime.sessionFor(
                  workspace: workspaceWithPath(path),
                  tab: tab,
                );
                return AnimatedBuilder(
                  animation: session,
                  builder: (context, _) => Text(session.displayTitle),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Mutating the workspace path makes sync() detect a metadata change while
      // the AnimatedBuilder is mounted and listening.
      pathNotifier.value = '/tmp/b';
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  test('runtime applies visual settings to existing sessions', () {
    final initialSettings = TerminalSettings.defaults.copyWith(
      fontFamily: 'monospace',
    );
    final runtime = XtermTerminalRuntime(initialSettings: initialSettings);
    addTearDown(runtime.dispose);
    final session = runtime.sessionFor(workspace: _workspace(), tab: _tab());
    var notifications = 0;
    session.addListener(() => notifications++);

    runtime.updateSettings(
      initialSettings.copyWith(
        fontSize: 18,
        fontWeight: 500,
        cursorBlink: true,
        themeName: 'Tokyo Night',
      ),
    );

    final view = session.buildView() as xterm.TerminalView;
    final expectedTheme = terminalThemeForName('Tokyo Night');
    expect(notifications, 1);
    expect(view.textStyle.fontSize, 18);
    expect(view.textStyle.fontWeight, 500);
    expect(view.cursorBlink, isTrue);
    expect(view.theme.background, expectedTheme.background);
  });

  testWidgets('defers startup notifications until after the first frame', (
    tester,
  ) async {
    final session = _ImmediateNotifySessionHandle(tabId: 'tab-1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: session)),
        ),
      ),
    );
    await tester.pump();

    expect(session.ensureStartedCallCount, 1);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('restarts deferred startup when the session changes', (
    tester,
  ) async {
    final first = _ImmediateNotifySessionHandle(tabId: 'tab-1');
    final second = _ImmediateNotifySessionHandle(tabId: 'tab-2');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: first)),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: TerminalSurface(session: second)),
        ),
      ),
    );
    await tester.pump();

    expect(first.ensureStartedCallCount, 1);
    expect(second.ensureStartedCallCount, 1);
    expect(
      find.byKey(const ValueKey<String>('terminal-tab-2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

WorkspaceTabRecord _tab() {
  return WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: 'ws-1',
    title: 'Terminal 1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

Workspace _workspace({String path = '/tmp/alera'}) {
  return Workspace(
    id: 'ws-1',
    projectId: 'p-1',
    name: 'Main',
    branch: 'main',
    path: path,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

class _FakeTerminalPtySessionFactory implements TerminalPtySessionFactory {
  final List<_FakeTerminalPtySession> sessions = <_FakeTerminalPtySession>[];

  @override
  TerminalPtySession create() {
    final session = _FakeTerminalPtySession();
    sessions.add(session);
    return session;
  }
}

class _FakeTerminalPtySession implements TerminalPtySession {
  final StreamController<TerminalPtySessionEvent> _events =
      StreamController<TerminalPtySessionEvent>.broadcast();
  GhosttyTerminalShellLaunch? startedLaunch;
  int? startedCols;
  int? startedRows;
  bool disposed = false;
  int? exitCodeOnDispose;

  @override
  Stream<TerminalPtySessionEvent> get events => _events.stream;

  @override
  Future<void> start({
    required GhosttyTerminalShellLaunch launch,
    required int cols,
    required int rows,
  }) async {
    startedLaunch = launch;
    startedCols = cols;
    startedRows = rows;
  }

  @override
  bool writeBytes(List<int> bytes) => bytes.isNotEmpty;

  @override
  void resize(int cols, int rows, int cellWidthPx, int cellHeightPx) {}

  void emitExit(int exitCode) {
    if (_events.isClosed) {
      return;
    }
    _events.add(TerminalPtyExitEvent(exitCode));
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposed = true;
    if (exitCodeOnDispose case final exitCode?) {
      _events.add(TerminalPtyExitEvent(exitCode));
    }
    unawaited(_events.close());
  }
}

class _ImmediateNotifySessionHandle extends TerminalSessionHandle {
  _ImmediateNotifySessionHandle({required this.tabId});

  @override
  final String tabId;

  int ensureStartedCallCount = 0;
  bool _started = false;

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => !_started;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    ensureStartedCallCount += 1;
    _started = true;
    notifyListeners();
  }

  @override
  Future<void> restart() => ensureStarted();

  @override
  Widget buildView({Key? key, bool autofocus = false}) {
    return SizedBox.expand(key: ValueKey<String>('terminal-$tabId'));
  }

  @override
  void requestFocus() {}
}
