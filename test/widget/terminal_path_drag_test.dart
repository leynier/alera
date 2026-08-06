import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_drop_target.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('path drag pastes paths and focuses the terminal', (
    tester,
  ) async {
    final session = _CapturingTerminalSessionHandle();

    await _pumpDragHarness(tester, session);
    await _dragSourceToTerminal(tester);

    expect(session.pasted, <String>["/tmp/foo '/tmp/my file' "]);
    expect(session.focusRequests, 1);
  });

  testWidgets('vertical pans prefer scroll over path drag', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: ListView(
              children: <Widget>[
                SizedBox(
                  height: 80,
                  child: Center(
                    child: TerminalPathDraggable<TerminalPathDragData>(
                      data: const TerminalPathDragData(
                        paths: <String>['/tmp/foo'],
                      ),
                      feedback: const Material(child: Text('Dragging Paths')),
                      child: const Text('Drag Paths'),
                    ),
                  ),
                ),
                const SizedBox(height: 400, child: Text('Below')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Drag Paths')),
    );
    await gesture.moveBy(const Offset(0, -(kTouchSlop + 20)));
    await tester.pump();
    expect(find.text('Dragging Paths'), findsNothing);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('sub-touch-slop mouse moves keep competing taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => taps += 1,
              child: TerminalPathDraggable<TerminalPathDragData>(
                data: const TerminalPathDragData(paths: <String>['/tmp/foo']),
                feedback: const Material(child: Text('Dragging Paths')),
                child: const Text('Drag Paths'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Use a mouse pointer so the test fails if we regress to ImmediateMultiDrag
    // (kPrecisePointerHitSlop = 1px) instead of kTouchSlop.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Drag Paths')),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(find.text('Dragging Paths'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('terminal error state rejects in-app path drags', (tester) async {
    final session = _CapturingTerminalSessionHandle(error: 'unavailable');

    await _pumpDragHarness(tester, session);
    await _dragSourceToTerminal(tester);

    expect(session.pasted, isEmpty);
    expect(session.focusRequests, 0);
  });

  testWidgets('composer turns in-app path drags into attachments', (
    tester,
  ) async {
    final session = _CapturingTerminalSessionHandle();
    session.composerController.show();

    await _pumpDragHarness(
      tester,
      session,
      paths: const <String>['/tmp/image.png', '/tmp/my file'],
    );
    await _dragSourceToTerminal(
      tester,
      target: find.byKey(session.composerController.dropTargetKey),
    );

    expect(session.pasted, isEmpty);
    expect(session.composerController.attachments, hasLength(2));
    expect(
      session.composerController.attachments.map(
        (attachment) => attachment.kind,
      ),
      <TerminalComposerAttachmentKind>[
        TerminalComposerAttachmentKind.image,
        TerminalComposerAttachmentKind.file,
      ],
    );
  });

  testWidgets('composer turns desktop file drops into attachments', (
    tester,
  ) async {
    final session = _CapturingTerminalSessionHandle();
    session.composerController.show();
    await _pumpDragHarness(tester, session);

    handleTerminalFileDrop(
      session: session,
      paths: const <String>['/tmp/image.webp', '/tmp/report.pdf'],
      globalPosition: tester.getCenter(
        find.byKey(session.composerController.dropTargetKey),
      ),
    );
    await tester.pump();

    expect(session.pasted, isEmpty);
    expect(session.composerController.attachments, hasLength(2));
  });
}

Future<void> _pumpDragHarness(
  WidgetTester tester,
  _CapturingTerminalSessionHandle session, {
  List<String> paths = const <String>['/tmp/foo', '/tmp/my file'],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(
              width: 200,
              child: Center(
                child: TerminalPathDraggable<TerminalPathDragData>(
                  data: TerminalPathDragData(paths: paths),
                  feedback: const Material(child: Text('Dragging Paths')),
                  child: const Text('Drag Paths'),
                ),
              ),
            ),
            Expanded(child: TerminalSurface(session: session)),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _dragSourceToTerminal(
  WidgetTester tester, {
  Finder? target,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Drag Paths')),
  );
  // Path drag starts after horizontal touch slop, not after long-press.
  await gesture.moveBy(const Offset(kTouchSlop + 1, 0));
  await tester.pump();
  expect(find.text('Dragging Paths'), findsOneWidget);

  await gesture.moveTo(
    tester.getCenter(target ?? find.byType(TerminalSurface)),
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

class _CapturingTerminalSessionHandle extends TerminalSessionHandle {
  _CapturingTerminalSessionHandle({this.error});

  final String? error;
  final List<String> pasted = <String>[];
  int focusRequests = 0;
  final ValueNotifier<String> _title = ValueNotifier<String>('Terminal');

  @override
  String get tabId => 'tab';

  @override
  String get workspaceId => 'workspace';

  @override
  String get displayTitle => 'Terminal';

  @override
  ValueListenable<String> get titleListenable => _title;

  @override
  bool get isRunning => error == null;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => error;

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
    return const ColoredBox(color: Colors.black);
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
