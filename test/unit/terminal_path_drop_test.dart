import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('resolves terminal paths with the active platform context', () {
    expect(
      terminalAbsolutePath(
        rootPath: '/tmp/project',
        relativePath: 'packages/app/main.dart',
        pathContext: p.Context(style: p.Style.posix),
      ),
      '/tmp/project/packages/app/main.dart',
    );
  });

  test('resolves Git paths with Windows separators', () {
    expect(
      terminalAbsolutePath(
        rootPath: r'C:\project',
        relativePath: 'packages/app/main.dart',
        pathContext: p.Context(style: p.Style.windows),
      ),
      r'C:\project\packages\app\main.dart',
    );
  });

  test('keeps the root path for an empty relative path', () {
    expect(
      terminalAbsolutePath(rootPath: '/tmp/project', relativePath: ''),
      '/tmp/project',
    );
  });

  test('pastes formatted paths and requests focus', () {
    final session = _CapturingTerminalSessionHandle();

    handleTerminalPathDrop(
      session: session,
      paths: <String>['/tmp/foo', '/tmp/my file'],
    );

    expect(session.pasted, <String>["/tmp/foo '/tmp/my file' "]);
    expect(session.focusRequests, 1);
  });

  test('pastes workspace files relative to the workspace root', () {
    final session = _CapturingTerminalSessionHandle()
      ..workspacePath = '/tmp/project';

    handleTerminalPathDrop(
      session: session,
      paths: <String>[
        '/tmp/project/packages/app/main.dart',
        '/tmp/project/my file.txt',
        '/tmp/other/absolute.txt',
      ],
    );

    expect(session.pasted, <String>[
      "${p.join('packages', 'app', 'main.dart')} 'my file.txt' "
          '/tmp/other/absolute.txt ',
    ]);
    expect(session.focusRequests, 1);
  });

  test('ignores empty path lists', () {
    final session = _CapturingTerminalSessionHandle();

    handleTerminalPathDrop(session: session, paths: <String>['', '  ']);

    expect(session.pasted, isEmpty);
    expect(session.focusRequests, 0);
  });
}

class _CapturingTerminalSessionHandle extends TerminalSessionHandle {
  final List<String> pasted = <String>[];
  int focusRequests = 0;
  final ValueNotifier<String> _title = ValueNotifier<String>('Terminal');

  @override
  String? workspacePath;

  @override
  String get tabId => 'tab';

  @override
  String get workspaceId => 'workspace';

  @override
  String get displayTitle => 'Terminal';

  @override
  ValueListenable<String> get titleListenable => _title;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

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
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return const SizedBox.shrink();
  }

  @override
  void requestFocus() {
    focusRequests += 1;
  }

  @override
  void pasteText(String text) {
    pasted.add(text);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }
}
