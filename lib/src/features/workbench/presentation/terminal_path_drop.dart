import 'package:alera/src/features/workbench/domain/terminal_path_paste.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

String terminalAbsolutePath({
  required String rootPath,
  required String relativePath,
  p.Context? pathContext,
}) {
  if (relativePath.isEmpty) {
    return rootPath;
  }
  return (pathContext ?? p.context).joinAll(<String>[
    rootPath,
    ...relativePath.split('/'),
  ]);
}

abstract interface class TerminalPathDragPayload {
  Iterable<String> get paths;
}

class TerminalPathDragData implements TerminalPathDragPayload {
  const TerminalPathDragData({required this.paths});

  @override
  final List<String> paths;
}

/// Path drag source for explorer and source control rows.
///
/// Starts after horizontal touch slop rather than [kLongPressTimeout], matching
/// desktop file-tree drag latency. Uses a horizontal multi-drag recognizer with
/// [kTouchSlop] for every pointer kind so:
/// - vertical pans still scroll the parent list
/// - mouse clicks with a few pixels of drift still fire row [onTap] (plain
///   [Draggable] uses [kPrecisePointerHitSlop] of 1px for mice and steals taps)
///
/// Explorer long-press / secondary-click context menus stay on a separate
/// gesture detector outside this widget.
class TerminalPathDraggable<T extends TerminalPathDragPayload>
    extends StatelessWidget {
  const TerminalPathDraggable({
    super.key,
    required this.data,
    required this.feedback,
    required this.child,
  });

  final T data;
  final Widget feedback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _TerminalPathDragSource<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }
}

/// [Draggable] that recognizes path drags with horizontal [kTouchSlop].
class _TerminalPathDragSource<T extends Object> extends Draggable<T> {
  const _TerminalPathDragSource({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
  }) : super(affinity: Axis.horizontal);

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _TerminalPathDragGestureRecognizer(
      debugOwner: this,
      allowedButtonsFilter: allowedButtonsFilter,
    )..onStart = onStart;
  }
}

/// Horizontal multi-drag that uses [kTouchSlop] for all pointer kinds.
///
/// [HorizontalMultiDragGestureRecognizer] still calls [computeHitSlop], which
/// is 1px for mice. That is too tight next to row taps ([kTouchSlop] = 18).
class _TerminalPathDragGestureRecognizer extends MultiDragGestureRecognizer {
  _TerminalPathDragGestureRecognizer({
    super.debugOwner,
    super.allowedButtonsFilter,
  });

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _TerminalPathDragPointerState(
      event.position,
      event.kind,
      gestureSettings,
    );
  }

  @override
  String get debugDescription => 'terminal path drag';
}

class _TerminalPathDragPointerState extends MultiDragPointerState {
  _TerminalPathDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  @override
  void checkForResolutionAfterMove() {
    assert(pendingDelta != null);
    final slop = gestureSettings?.touchSlop ?? kTouchSlop;
    if (pendingDelta!.dx.abs() > slop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

/// Pastes absolute paths into [session] after an OS or in-app drop.
void handleTerminalPathDrop({
  required TerminalSessionHandle session,
  required Iterable<String> paths,
}) {
  final text = formatPathsForTerminalPaste(paths);
  if (text.isEmpty) {
    return;
  }
  session.pasteText(text);
  session.requestFocus();
}
