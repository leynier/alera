import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceDetailsPresence({
  super.key,
  required this.scope,
  required this.child,
}) extends ConsumerStatefulWidget {
  final WorkspacePullRequestScope scope;
  final Widget child;
  @override
  ConsumerState<WorkspaceDetailsPresence> createState() =>
      _WorkspaceDetailsPresenceState();
}

class _WorkspaceDetailsPresenceState
    extends ConsumerState<WorkspaceDetailsPresence> {
  WorkspacePullRequestController? _controller;
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(WorkspaceDetailsPresence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _release();
      _controller = null;
    }
    _sync();
  }

  void _sync() {
    if (TickerMode.valuesOf(context).enabled == _attached) return;
    if (TickerMode.valuesOf(context).enabled) {
      _controller ??= ref.read(
        workspacePullRequestControllerProvider(widget.scope).notifier,
      );
      _controller!.attachPanel();
      _attached = true;
    } else {
      _release();
    }
  }

  void _release() {
    if (_attached) _controller?.detachPanel();
    _attached = false;
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspacePullRequestControllerProvider(widget.scope).notifier, (
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
