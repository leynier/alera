import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workspace_terminal_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a snapshot starting after readiness defers the queued refresh', (
    tester,
  ) async {
    final session = _RefreshSession();
    final runtime = _RefreshRuntime(session);
    addTearDown(session.dispose);
    await _pumpRefresh(tester, runtime);
    await tester.pump();
    expect(session.isObserved, isTrue);
    session.progress.value = const TerminalRestoreProgress(
      writtenChars: 0,
      totalChars: 100,
    );
    await tester.pump();
    expect(session.refreshes, 0);
    session.progress.value = null;
    await tester.pumpAndSettle();
    expect(session.refreshes, 1);
    expect(session.isObserved, isFalse);
  });

  for (final restoring in [false, true]) {
    for (final unmount in [false, true]) {
      testWidgets(
        'closing a ${restoring ? 'restoring' : 'starting'} tab clears waits '
        'before ${unmount ? 'unmount' : 'workspace change'}',
        (tester) async {
          final session = _RefreshSession()..starting = !restoring;
          if (restoring) {
            session.progress.value = const TerminalRestoreProgress(
              writtenChars: 0,
              totalChars: 100,
            );
          }
          final runtime = _RefreshRuntime(session);
          await _pumpRefresh(tester, runtime);
          await tester.pumpAndSettle();
          expect(session.isObserved, isTrue);
          runtime.session = null;
          session.dispose();
          expect(session.isObserved, isFalse);
          expect(session.removedAfterDisposal, 0);
          if (unmount) {
            await tester.pumpWidget(const SizedBox.shrink());
          } else {
            await _pumpRefresh(
              tester,
              runtime,
              workspaceId: 'another-workspace',
            );
          }
          await tester.pumpAndSettle();
          expect(session.removedAfterDisposal, 0);
          expect(session.refreshes, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('leaving a workspace removes pending restore subscriptions', (
    tester,
  ) async {
    final session = _RefreshSession();
    addTearDown(session.dispose);
    session.progress.value = const TerminalRestoreProgress(
      writtenChars: 0,
      totalChars: 100,
    );
    final runtime = _RefreshRuntime(session);
    await _pumpRefresh(tester, runtime);
    await tester.pumpAndSettle();
    await _pumpRefresh(tester, runtime, workspaceId: 'another-workspace');
    expect(session.isObserved, isFalse);
    session.progress.value = null;
    await tester.pumpAndSettle();
    expect(session.refreshes, 0);
  });
}

Future<void> _pumpRefresh(
  WidgetTester tester,
  _RefreshRuntime runtime, {
  String workspaceId = 'workspace',
}) => tester.pumpWidget(
  MaterialApp(
    home: WorkspaceTerminalRefresh(
      workspaceId: workspaceId,
      ready: true,
      terminalTabIds: const ['tab'],
      terminalRuntime: runtime,
      child: const SizedBox.expand(),
    ),
  ),
);

class _RefreshRuntime(var TerminalSessionHandle? session)
    implements TerminalRuntime {
  @override
  TerminalSessionHandle? peekSession(String tabId) => session;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RefreshSession extends TerminalSessionHandle {
  bool starting = false;
  bool disposed = false;
  int refreshes = 0;
  int removedAfterDisposal = 0;
  final progress = ValueNotifier<TerminalRestoreProgress?>(null);
  final title = ValueNotifier('Terminal');

  bool get isObserved => hasListeners;

  @override
  void removeListener(VoidCallback listener) {
    if (disposed) removedAfterDisposal++;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    super.dispose();
    disposed = true;
    progress.dispose();
    title.dispose();
    composerController.dispose();
  }

  @override
  String get tabId => 'tab';
  @override
  String get workspaceId => 'workspace';
  @override
  bool get isVisible => true;
  @override
  bool get isStarting => starting;
  @override
  bool get isRunning => !starting;
  @override
  String get displayTitle => title.value;
  @override
  ValueListenable<String> get titleListenable => title;
  @override
  ValueListenable<TerminalRestoreProgress?> get restoreProgress => progress;
  @override
  String? get errorMessage => null;
  @override
  Future<void> ensureStarted() async {}
  @override
  Future<void> restart() async {}
  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();
  @override
  void requestFocus() {}
  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox.expand();
  @override
  Future<void> refreshRendering() async {
    refreshes++;
  }
}
