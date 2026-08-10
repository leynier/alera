import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_providers.dart'
    hide AgentUsageProvider;
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_usage_dialog_content.dart';
part 'agent_usage_daily_chart.dart';
part 'agent_usage_format.dart';

Future<void> openAgentUsageDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const AgentUsageDialog(),
  );
}

class AgentUsageDialog extends ConsumerStatefulWidget {
  const AgentUsageDialog({super.key});

  @override
  ConsumerState<AgentUsageDialog> createState() => _AgentUsageDialogState();
}

class _AgentUsageDialogState extends ConsumerState<AgentUsageDialog> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final hostId = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.hostId ?? 'local',
      ),
    );
    final usage = ref.watch(agentUsageProvider(_days));
    final quota = ref.watch(agentQuotaStateProvider);
    final snapshot = usage.value;
    return AgentUsageDialogView(
      hostId: hostId,
      days: _days,
      snapshot: snapshot,
      quotaSnapshots: quota.value?.snapshots ?? const <AgentQuotaSnapshot>[],
      loading: usage.isLoading,
      error: usage.hasError ? usage.error.toString() : null,
      onDaysChanged: (days) => setState(() => _days = days),
      onRefresh: () {
        ref.invalidate(agentUsageProvider(_days));
        ref.read(agentQuotaServiceProvider).requestForceRefresh(hostId);
        ref.invalidate(agentQuotaStateProvider);
      },
      onClose: () => Navigator.of(context).pop(),
    );
  }
}

class AgentUsageDialogView extends StatelessWidget {
  const AgentUsageDialogView({
    super.key,
    required this.hostId,
    required this.days,
    required this.snapshot,
    required this.quotaSnapshots,
    required this.loading,
    required this.error,
    required this.onDaysChanged,
    required this.onRefresh,
    required this.onClose,
  });

  final String hostId;
  final int days;
  final AgentUsageSnapshot? snapshot;
  final List<AgentQuotaSnapshot> quotaSnapshots;
  final bool loading;
  final String? error;
  final ValueChanged<int> onDaysChanged;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: AleraTokens.usageDialogWidth,
      maxHeight: AleraTokens.usageDialogMaxHeight,
      child: SizedBox(
        width: AleraTokens.usageDialogWidth,
        height: AleraTokens.usageDialogMaxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space20,
                AleraTokens.space16,
                AleraTokens.space12,
                AleraTokens.space12,
              ),
              child: AleraDialogHeader(
                title: 'Usage',
                onClose: onClose,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      hostId == 'local' ? 'Local Host' : hostId,
                      style: AleraTokens.monoCompactStyle,
                    ),
                    const SizedBox(width: AleraTokens.space12),
                    AleraSegmentedButton<int>(
                      dense: true,
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 7, label: Text('7 Days')),
                        ButtonSegment<int>(value: 30, label: Text('30 Days')),
                        ButtonSegment<int>(value: 90, label: Text('90 Days')),
                      ],
                      selected: days,
                      onSelectionChanged: onDaysChanged,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    AleraIconButton(
                      tooltip: 'Refresh Usage',
                      icon: AleraIcons.refresh,
                      onPressed: loading ? null : onRefresh,
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              const LinearProgressIndicator(minHeight: AleraTokens.space2),
            const Divider(height: 1, color: AleraTokens.borderSubtle),
            Expanded(
              child: snapshot == null
                  ? _UsageUnavailable(
                      loading: loading,
                      error: error,
                      onRefresh: onRefresh,
                    )
                  : _AgentUsageContent(
                      snapshot: snapshot!,
                      quotas: quotaSnapshots,
                      refreshing: loading,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageUnavailable extends StatelessWidget {
  const _UsageUnavailable({
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AleraEmptyState(
      icon: AleraIcons.quota,
      title: 'Usage Unavailable',
      message: error ?? 'No usage data is available for this host.',
      action: OutlinedButton(
        onPressed: onRefresh,
        child: const Text('Try Again'),
      ),
    );
  }
}
