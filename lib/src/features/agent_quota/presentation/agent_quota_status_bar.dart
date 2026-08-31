import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_usage/presentation/agent_usage_dialog.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_quota_status_bar_content.dart';
import 'agent_quota_inline_actions.dart';

export 'agent_quota_status_bar_content.dart' show AgentQuotaPinToggle;

part 'agent_quota_codex_reset.dart';
part 'agent_quota_claude_tui.dart';

class const AgentQuotaStatusBar({super.key, final Widget? trailing})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostId = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.hostId ?? 'local',
      ),
    );
    final settings = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.agents.quotas.forHost(hostId),
      ),
    );
    final quota = ref.watch(agentQuotaStateProvider);
    final state = quota.value;
    void refresh() {
      ref.read(agentQuotaServiceProvider).requestForceRefresh(hostId);
      ref.invalidate(agentQuotaStateProvider);
    }

    void togglePinned(String pinKey, bool pinned) {
      unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setAgentQuotaPinned(
              hostId: hostId,
              pinKey: pinKey,
              pinned: pinned,
            ),
      );
    }

    if (state != null) {
      return AgentQuotaStatusBarView(
        hostId: state.hostId,
        snapshots: state.snapshots,
        settings: settings,
        error: state.error,
        loading: quota.isLoading,
        onRefresh: refresh,
        onTogglePinned: togglePinned,
        onOpenUsage: () => unawaited(openAgentUsageDialog(context)),
        trailing: trailing,
      );
    }
    return quota.when(
      loading: () => AgentQuotaStatusBarView(
        hostId: hostId,
        snapshots: const <AgentQuotaSnapshot>[],
        settings: settings,
        loading: true,
        onRefresh: refresh,
        onTogglePinned: togglePinned,
        onOpenUsage: () => unawaited(openAgentUsageDialog(context)),
        trailing: trailing,
      ),
      error: (error, _) => AgentQuotaStatusBarView(
        hostId: hostId,
        snapshots: const <AgentQuotaSnapshot>[],
        settings: settings,
        error: error.toString(),
        onRefresh: refresh,
        onTogglePinned: togglePinned,
        onOpenUsage: () => unawaited(openAgentUsageDialog(context)),
        trailing: trailing,
      ),
      data: (_) => AgentQuotaStatusBarView(
        hostId: hostId,
        snapshots: const <AgentQuotaSnapshot>[],
        settings: settings,
        loading: true,
        onRefresh: refresh,
        onTogglePinned: togglePinned,
        onOpenUsage: () => unawaited(openAgentUsageDialog(context)),
        trailing: trailing,
      ),
    );
  }
}

// Keep runtime actions outside the library compiled by Flutter web previews.
class const AgentQuotaStatusBarView({
  super.key,
  required super.hostId,
  required super.snapshots,
  required super.settings,
  required super.onRefresh,
  required super.onTogglePinned,
  super.loading,
  super.error,
  super.trailing,
  super.onOpenUsage,
}) extends AgentQuotaStatusBarContent {
  this
    : super(
        actions: const AgentQuotaInlineActions(
          codexReset: _buildCodexReset,
          claudeTui: _buildClaudeTui,
        ),
      );
}

Widget _buildCodexReset({
  required String hostId,
  required AgentQuotaSnapshot snapshot,
  required bool compact,
}) => _CodexResetCreditsPanel(
  hostId: hostId,
  snapshot: snapshot,
  compact: compact,
);

Widget _buildClaudeTui({
  required String hostId,
  required AgentQuotaSnapshot snapshot,
  required bool compact,
}) => _ClaudeTryWithTuiButton(hostId: hostId, snapshot: snapshot);
