import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:flutter/material.dart';

/// Visual state glyph for one agent run: spinner while working, state-colored
/// icon otherwise. Shared by agent rows and the compact summary.
class const AgentRunStateIndicator({
  super.key,
  required final AgentPresenceSummary status,
  final double size = 13,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = agentRunStateLabel(status);
    final color = agentRunStateColor(status);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: _buildIndicator(color)),
        ),
      ),
    );
  }

  Widget _buildIndicator(Color color) {
    if (status.state == 'working' && status.interrupted != true) {
      return SizedBox.square(
        dimension: size - 2,
        child: const CircularProgressIndicator(
          strokeWidth: 1.7,
          color: AleraTokens.warning,
        ),
      );
    }
    final icon = status.interrupted == true
        ? AleraIcons.cancel
        : switch (status.state) {
            'done' => AleraIcons.success,
            'waiting' || 'blocked' => AleraIcons.notifications,
            'working' => AleraIcons.sync,
            _ => AleraIcons.success,
          };
    return Icon(icon, size: size, color: color);
  }
}

Color agentRunStateColor(AgentPresenceSummary status) {
  if (status.interrupted == true) {
    return AleraTokens.error;
  }
  return switch (status.state) {
    'working' => AleraTokens.warning,
    'waiting' => AleraTokens.warning,
    'blocked' => AleraTokens.error,
    _ => AleraTokens.success,
  };
}

String agentRunStateLabel(AgentPresenceSummary status) {
  if (status.interrupted == true) {
    return 'Interrupted';
  }
  return switch (status.state) {
    'working' => 'Working',
    'waiting' => 'Waiting for input',
    'blocked' => 'Blocked',
    _ => 'Done',
  };
}
