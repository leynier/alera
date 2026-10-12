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
  late final WorkspacePullRequestController _controller;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(
      workspacePullRequestControllerProvider(widget.scope).notifier,
    );
    _controller.attachPanel();
  }

  @override
  void dispose() {
    _controller.detachPanel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
