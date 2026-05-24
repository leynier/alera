import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'changing workspace metadata during build does not notify synchronously',
    (tester) async {
      final runtime = XtermTerminalRuntime();
      addTearDown(runtime.dispose);
      final tab = TerminalTabRecord(
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
    expect(find.byKey(const ValueKey<String>('terminal-tab-1')), findsOneWidget);
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
    expect(find.byKey(const ValueKey<String>('terminal-tab-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
}
