import 'package:alera/src/features/workbench/domain/terminal_path_paste.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
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

/// Immediate-path drag source for explorer and source control rows.
///
/// Uses [Draggable] rather than [LongPressDraggable] so desktop pointer drags
/// start after touch slop instead of waiting for [kLongPressTimeout]. Long-press
/// context menus on those rows stay on a separate gesture detector.
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
    return Draggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
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
