import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lease for a Git surface mounted in the selected workspace. Retained,
/// offstage workbench content releases it through TickerMode.
class const WorkspaceSourceControlPresence({
  super.key,
  required final String path,
  required final Widget child,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceSourceControlPresence> createState() =>
      _WorkspaceSourceControlPresenceState();
}

class _WorkspaceSourceControlPresenceState
    extends ConsumerState<WorkspaceSourceControlPresence> {
  WorkspaceSourceControlController? _controller;
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WorkspaceSourceControlPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _release();
      _controller = null;
    }
    _sync();
  }

  void _sync() {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _attached) return;
    if (visible) {
      _controller ??= ref.read(
        workspaceSourceControlControllerProvider(widget.path).notifier,
      );
      _controller!.attachView();
      _attached = true;
    } else {
      _release();
    }
  }

  void _release() {
    if (_attached) _controller?.detachView();
    _attached = false;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceSourceControlControllerProvider(widget.path).notifier, (
      previous,
      next,
    ) {
      if (identical(_controller, next)) return;
      _release();
      _controller = next;
      _sync();
    });
    return widget.child;
  }
}
