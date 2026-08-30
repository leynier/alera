import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/automation_detail_tabs.dart';
import 'package:flutter/material.dart';

class const AutomationDialogHeader({
  required final VoidCallback onClose,
  final VoidCallback? onImport,
  final VoidCallback? onExport,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        const Icon(AleraIcons.checks, color: AleraTokens.foregroundMuted),
        const SizedBox(width: AleraTokens.space8),
        Expanded(child: Text('Automations', style: theme.textTheme.titleLarge)),
        if (onImport != null)
          AleraIconButton(
            tooltip: 'Import',
            icon: AleraIcons.download,
            onPressed: onImport,
          ),
        if (onExport != null)
          AleraIconButton(
            tooltip: 'Export',
            icon: AleraIcons.cloudUpload,
            onPressed: onExport,
          ),
        AleraIconButton(
          tooltip: 'Close',
          icon: AleraIcons.close,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class const AutomationListRow({
  required final AutomationRecord automation,
  required final bool selected,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: AleraTokens.accentSubtle,
      onTap: onTap,
      title: Text(automation.name, maxLines: 1, overflow: .ellipsis),
      subtitle: Text(
        '${automation.state} · ${automation.scheduleKind}',
        maxLines: 1,
        overflow: .ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
      trailing: automation.isApproved
          ? const Icon(AleraIcons.secure, size: 15, color: AleraTokens.success)
          : const Icon(
              AleraIcons.warning,
              size: 15,
              color: AleraTokens.warning,
            ),
    );
  }
}

class const AutomationDetailPane({
  required final Future<AutomationDetail> future,
  required final VoidCallback onRefresh,
  required final VoidCallback onEdit,
  required final VoidCallback? onApprove,
  required final VoidCallback onRunNow,
  required final VoidCallback? onPause,
  required final VoidCallback? onResume,
  required final VoidCallback? onTrash,
  final ValueChanged<AutomationRunRecord>? onCancel,
  final ValueChanged<AutomationRunRecord>? onResumeWaiting,
  final ValueChanged<AutomationRunRecord>? onExtendWaiting,
  final VoidCallback? onRestore,
  final VoidCallback? onClone,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AutomationDetail>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return AleraEmptyState(
            icon: AleraIcons.error,
            title: 'Automation unavailable',
            message: snapshot.error.toString(),
            action: FilledButton(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return const AleraEmptyState(
            message: 'No automation details available.',
          );
        }
        return AutomationDetailContent(
          detail: detail,
          onRefresh: onRefresh,
          onEdit: onEdit,
          onApprove: onApprove,
          onRunNow: onRunNow,
          onPause: onPause,
          onResume: onResume,
          onTrash: onTrash,
          onRestore: onRestore,
          onClone: onClone,
          onCancel: onCancel,
          onResumeWaiting: onResumeWaiting,
          onExtendWaiting: onExtendWaiting,
        );
      },
    );
  }
}

class const AutomationDetailContent({
  required final AutomationDetail detail,
  required final VoidCallback onRefresh,
  required final VoidCallback onEdit,
  required final VoidCallback? onApprove,
  required final VoidCallback onRunNow,
  required final VoidCallback? onPause,
  required final VoidCallback? onResume,
  required final VoidCallback? onTrash,
  final ValueChanged<AutomationRunRecord>? onCancel,
  final ValueChanged<AutomationRunRecord>? onResumeWaiting,
  final ValueChanged<AutomationRunRecord>? onExtendWaiting,
  final VoidCallback? onRestore,
  final VoidCallback? onClone,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final automation = detail.automation;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(automation.name, style: theme.textTheme.titleMedium),
            ),
            Text(automation.state, style: theme.textTheme.bodySmall),
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: AleraIcons.refresh,
              onPressed: onRefresh,
            ),
            AleraIconButton(
              tooltip: 'Edit',
              icon: AleraIcons.edit,
              onPressed: onEdit,
            ),
            if (onClone != null)
              AleraIconButton(
                tooltip: 'Clone',
                icon: AleraIcons.copy,
                onPressed: onClone,
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space12),
        Wrap(
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            if (onApprove != null)
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(AleraIcons.secure, size: 16),
                label: const Text('Approve'),
              ),
            FilledButton.icon(
              onPressed: onRunNow,
              icon: const Icon(AleraIcons.agent, size: 16),
              label: const Text('Run Now'),
            ),
            OutlinedButton(
              onPressed: onPause ?? onResume,
              child: Text(onPause != null ? 'Pause' : 'Resume'),
            ),
            if (onRestore != null)
              TextButton(onPressed: onRestore, child: const Text('Restore'))
            else
              TextButton(onPressed: onTrash, child: const Text('Trash')),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        Expanded(
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: <Widget>[
                const TabBar(
                  tabs: <Widget>[
                    Tab(text: 'Overview'),
                    Tab(text: 'Runs'),
                    Tab(text: 'Audit'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      AutomationOverviewTab(detail: detail),
                      AutomationRunsTab(
                        runs: detail.runs,
                        onCancel: onCancel,
                        onResumeWaiting: onResumeWaiting,
                        onExtendWaiting: onExtendWaiting,
                      ),
                      AutomationAuditTab(events: detail.audit),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class const AutomationInfoPanel({
  required final AutomationRecord automation,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final schedule =
        _nested(automation.schedule, 'recurring') ??
        _nested(automation.schedule, 'oneTime') ??
        automation.schedule;
    final targetKey = automation.target.isEmpty
        ? null
        : automation.target.keys.first;
    final target = _nested(automation.target, targetKey) ?? automation.target;
    return AleraPanel(
      children: <Widget>[
        AutomationInfoRow(label: 'Slug', value: automation.slug),
        AutomationInfoRow(
          label: 'Schedule',
          value:
              '${automation.scheduleKind} · ${schedule['timezone'] ?? 'UTC'}',
        ),
        AutomationInfoRow(
          label: 'Cron / time',
          value: '${schedule['cron'] ?? schedule['at'] ?? 'Not set'}',
        ),
        AutomationInfoRow(
          label: 'Target',
          value:
              '${automation.targetKind} · ${target['workspaceId'] ?? target['sourceWorkspaceId'] ?? 'Not set'}',
        ),
        AutomationInfoRow(
          label: 'Policies',
          value:
              'Setup ${automation.setupPolicy} · Overlap ${automation.overlapPolicy} · Misfire ${automation.misfirePolicy} · Cleanup ${automation.cleanupPolicy ?? 'preserve'}',
        ),
        AutomationInfoRow(
          label: 'Limits',
          value:
              'Queue ${automation.queueCap} · Inactivity ${automation.inactivityTimeoutSeconds}s · Heartbeat ${automation.heartbeatIntervalSeconds}s · Retries ${automation.retryMaxAttempts}',
        ),
        if (automation.projectId != null)
          AutomationInfoRow(label: 'Project', value: automation.projectId!),
        if (automation.tagIds.isNotEmpty)
          AutomationInfoRow(label: 'Tags', value: automation.tagIds.join(', ')),
        AutomationInfoRow(
          label: 'Revision',
          value:
              '${automation.revision}${automation.isApproved ? ' · approved' : ' · draft changes'}',
        ),
        if (automation.description.isNotEmpty)
          AutomationInfoRow(
            label: 'Description',
            value: automation.description,
          ),
        AutomationInfoRow(label: 'Prompt', value: automation.promptTemplate),
        AutomationInfoRow(
          label: 'Prompt Preview',
          value: _promptPreview(automation),
        ),
      ],
    );
  }

  JsonMap? _nested(JsonMap map, String? key) {
    final value = key == null ? null : map[key];
    return value is Map ? automationMap(value) : null;
  }
}

class const AutomationInfoRow({
  required final String label,
  required final String value,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: AleraTokens.automationInfoLabelWidth,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value, maxLines: 4, overflow: .ellipsis)),
        ],
      ),
    );
  }
}

JsonMap automationMap(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return <String, Object?>{};
}

String _promptPreview(AutomationRecord automation) {
  const known = <String>{
    'automation.id',
    'automation.name',
    'automation.slug',
    'run.id',
    'run.number',
    'run.scheduledAt',
    'workspace.id',
    'workspace.name',
    'workspace.path',
    'project.id',
    'project.name',
  };
  final values = <String, String>{
    'automation.id': automation.id,
    'automation.name': automation.name,
    'automation.slug': automation.slug,
  };
  final invalid = <String>[];
  final rendered = automation.promptTemplate.replaceAllMapped(
    RegExp(r'\{\{([^}]+)\}\}'),
    (match) {
      final variable = match.group(1)!.trim();
      if (!known.contains(variable)) {
        invalid.add(variable);
        return match.group(0)!;
      }
      return values[variable] ?? '<$variable>';
    },
  );
  if (invalid.isNotEmpty) {
    return 'Unknown prompt variable: ${invalid.toSet().join(', ')}';
  }
  return rendered;
}
