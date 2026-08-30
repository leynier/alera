import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:flutter/widgets.dart';

typedef AgentQuotaActionBuilder = Widget Function({
  required String hostId,
  required AgentQuotaSnapshot snapshot,
  required bool compact,
});

/// Optional runtime controls supplied by the native feature wrapper.
class AgentQuotaInlineActions {
  const AgentQuotaInlineActions({this.codexReset, this.claudeTui});

  final AgentQuotaActionBuilder? codexReset;
  final AgentQuotaActionBuilder? claudeTui;

  Widget buildCodexReset({
    required String hostId,
    required AgentQuotaSnapshot snapshot,
    bool compact = false,
  }) =>
      codexReset?.call(hostId: hostId, snapshot: snapshot, compact: compact) ??
      const SizedBox.shrink();

  Widget buildClaudeTui({
    required String hostId,
    required AgentQuotaSnapshot snapshot,
  }) =>
      claudeTui?.call(hostId: hostId, snapshot: snapshot, compact: false) ??
      const SizedBox.shrink();
}
