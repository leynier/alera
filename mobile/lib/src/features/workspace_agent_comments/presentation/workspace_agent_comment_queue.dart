import 'dart:async';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/terminal/application/agent_presence_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dispatch_sheet.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_draft_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('WorkspaceAgentCommentQueue');

/// Wires the comment draft bar to the workspace's queue and send flow. Renders
/// nothing while the queue is empty.
class const WorkspaceAgentCommentQueue({
  super.key,
  required final String hostId,
  required final String workspaceId,
  final ValueChanged<String>? onOpenTab,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WorkspaceAgentCommentQueue> createState() =>
      _WorkspaceAgentCommentQueueState();
}

class _WorkspaceAgentCommentQueueState
    extends ConsumerState<WorkspaceAgentCommentQueue> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final provider = workspaceAgentCommentControllerProvider(
      widget.hostId,
      widget.workspaceId,
    );
    final comments = ref.watch(provider);
    if (comments.isEmpty) {
      return const SizedBox.shrink();
    }
    final notifier = ref.read(provider.notifier);
    return WorkspaceAgentCommentDraftBar(
      comments: comments,
      sending: _sending,
      onSend: () => unawaited(_send()),
      onClear: notifier.clear,
      onRemove: notifier.remove,
    );
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final (runningAgents, profiles) = await (
        _runningAgents(),
        ref
            .read(
              tabsControllerProvider(
                widget.hostId,
                widget.workspaceId,
              ).notifier,
            )
            .listNewTabMenuProfiles(),
      ).wait;
      if (!mounted) {
        return;
      }
      final target = await showWorkspaceAgentCommentDispatchSheet(
        context,
        runningAgents: runningAgents,
        profiles: profiles,
      );
      if (target == null) {
        return;
      }
      final tabId = await ref
          .read(
            workspaceAgentCommentControllerProvider(
              widget.hostId,
              widget.workspaceId,
            ).notifier,
          )
          .sendTo(target);
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Comments sent to ${_targetLabel(target)}'),
            action: widget.onOpenTab == null
                ? null
                : SnackBarAction(
                    label: 'Open',
                    onPressed: () => widget.onOpenTab?.call(tabId),
                  ),
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      _logger.warning('could not send workspace comments', error, stackTrace);
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not send comments: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<List<AgentPresenceSummary>> _runningAgents() async {
    final presence = await ref.read(
      agentPresenceControllerProvider(widget.hostId).future,
    );
    return <AgentPresenceSummary>[
      for (final agent in presence)
        if (agent.workspaceId == widget.workspaceId) agent,
    ];
  }
}

String _targetLabel(WorkspaceAgentCommentTarget target) {
  return switch (target) {
    RunningAgentCommentTarget(:final agent) =>
      agent.title.trim().isEmpty ? agent.agentType : agent.title.trim(),
    AgentProfileCommentTarget(:final AgentProfileSummary profile) =>
      profile.name,
  };
}
