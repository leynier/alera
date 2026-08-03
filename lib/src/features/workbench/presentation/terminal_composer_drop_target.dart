import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

class TerminalComposerDropTarget extends StatelessWidget {
  const TerminalComposerDropTarget({
    super.key,
    required this.session,
    required this.child,
  });

  final TerminalSessionHandle session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final composer = session.composerController;
    return DragTarget<TerminalPathDragPayload>(
      onWillAcceptWithDetails: (_) => !composer.submitting,
      onAcceptWithDetails: (details) {
        composer.addPathAttachments(details.data.paths);
        composer.focusNode.requestFocus();
      },
      builder: (_, _, _) => child,
    );
  }
}

void handleTerminalFileDrop({
  required TerminalSessionHandle session,
  required Iterable<String> paths,
  required Offset globalPosition,
}) {
  final composer = session.composerController;
  final composerContext = composer.dropTargetKey.currentContext;
  final renderBox = composerContext?.findRenderObject();
  if (composer.visible &&
      !composer.submitting &&
      renderBox is RenderBox &&
      renderBox.paintBounds.contains(renderBox.globalToLocal(globalPosition))) {
    composer.addPathAttachments(paths);
    composer.focusNode.requestFocus();
    return;
  }
  handleTerminalPathDrop(session: session, paths: paths);
}
