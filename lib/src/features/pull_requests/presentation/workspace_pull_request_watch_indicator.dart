import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_agent_watch_providers.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_agent_watch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Eye glyph next to the pull-request status while Watch and Fix is active.
class const WorkspacePullRequestWatchIndicator({
  super.key,
  required this.workspaceId,
  this.size = 12,
}) extends ConsumerWidget {
  final String workspaceId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(
      pullRequestAgentWatchControllerProvider.select(
        (sessions) => sessions[workspaceId],
      ),
    );
    if (session == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: pullRequestAgentWatchTooltip(
            mode: session.mode,
            scope: session.watchScope,
          ),
          child: Icon(
            AleraIcons.visible,
            size: size,
            color: AleraTokens.foregroundMuted,
            key: const Key('workspace-tray-pr-watch'),
          ),
        ),
      ],
    );
  }
}
