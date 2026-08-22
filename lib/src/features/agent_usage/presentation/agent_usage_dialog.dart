import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/agent_usage/application/agent_usage_providers.dart'
    hide AgentUsageProvider;
import 'package:alera/src/features/agent_usage/application/agent_usage_period_memory.dart';
import 'package:alera/src/features/agent_usage/domain/agent_usage.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_usage_dialog_content.dart';
part 'agent_usage_daily_chart.dart';
part 'agent_usage_format.dart';
part 'agent_usage_metrics.dart';

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
  late int _days;

  @override
  void initState() {
    super.initState();
    _days = agentUsagePeriodMemory.days;
  }

  @override
  Widget build(BuildContext context) {
    final hostId = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.activeWorkspace?.hostId ?? 'local',
      ),
    );
    final usage = ref.watch(agentUsageProvider(_days));
    final quotaSettings = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.agents.quotas.forHost(hostId),
      ),
    );
    final usageState = usage.value;
    final snapshot = usageState?.snapshot;
    return AgentUsageDialogView(
      hostId: hostId,
      days: _days,
      snapshot: snapshot,
      showGroupedBreakdown:
          (quotaSettings.claudeDefaultShowInUsage ? 1 : 0) +
              quotaSettings.claudeProfiles
                  .where((profile) => profile.showInUsage)
                  .length >
          1,
      loading: usage.isLoading || (usageState?.refreshing ?? false),
      error: usage.hasError ? usage.error.toString() : usageState?.error,
      onDaysChanged: (days) {
        agentUsagePeriodMemory.select(days);
        setState(() => _days = days);
      },
      onRefresh: () => ref.read(agentUsageProvider(_days).notifier).refresh(),
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
    this.showGroupedBreakdown = true,
    required this.loading,
    required this.error,
    required this.onDaysChanged,
    required this.onRefresh,
    required this.onClose,
  });

  final String hostId;
  final int days;
  final AgentUsageSnapshot? snapshot;
  final bool showGroupedBreakdown;
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
                    if (loading && snapshot != null) ...<Widget>[
                      const SizedBox(width: AleraTokens.space12),
                      const _UsageLoadStatus(
                        icon: AleraIcons.sync,
                        label: 'Updating',
                        tooltip:
                            'Showing saved usage while new data loads in the background.',
                      ),
                    ] else if (error != null && snapshot != null) ...<Widget>[
                      const SizedBox(width: AleraTokens.space12),
                      _UsageLoadStatus(
                        icon: AleraIcons.warning,
                        label: 'Update Failed',
                        tooltip: error!,
                        color: AleraTokens.warning,
                      ),
                    ],
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
            if (loading && snapshot == null)
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
                      showGroupedBreakdown: showGroupedBreakdown,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageLoadStatus extends StatelessWidget {
  const _UsageLoadStatus({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color = AleraTokens.foregroundMuted,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AleraTokens.iconSm, color: color),
            const SizedBox(width: AleraTokens.space4),
            Text(
              label,
              style: AleraTokens.monoCompactStyle.copyWith(color: color),
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
