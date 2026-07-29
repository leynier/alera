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

class TerminalPathLongPressDraggable<T extends TerminalPathDragPayload>
    extends StatelessWidget {
  const TerminalPathLongPressDraggable({
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
    return LongPressDraggable<T>(
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
