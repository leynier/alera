import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_settings_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AgentQuotasScreen extends ConsumerWidget {
  const AgentQuotasScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotas = ref.watch(agentQuotaControllerProvider(host.id));
    final settings = ref.watch(hostSettingsControllerProvider(host.id)).value;
    final quotaValue = quotas.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotas'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Configure Quotas',
            onPressed: settings == null
                ? null
                : () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => QuotaSettingsScreen(host: host),
                    ),
                  ),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Refresh Quotas',
            onPressed: quotas.isLoading
                ? null
                : ref
                      .read(agentQuotaControllerProvider(host.id).notifier)
                      .refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: quotaValue != null
            ? _QuotaList(
                hostId: host.id,
                state: quotaValue,
                settings: settings?.agentQuotas,
                onRefresh: ref
                    .read(agentQuotaControllerProvider(host.id).notifier)
                    .refresh,
              )
            : quotas.hasError
            ? _QuotaError(error: quotas.error!, hostId: host.id)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _QuotaList extends ConsumerWidget {
  const _QuotaList({
    required this.hostId,
    required this.state,
    required this.settings,
    required this.onRefresh,
  });

  final String hostId;
  final QuotaSnapshotState state;
  final QuotaSettings? settings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = settings?.enabledProviders ?? supportedQuotaProviders;
    final snapshots = state.snapshots.toList()
      ..sort((left, right) {
        final leftIndex = order.indexOf(left.provider);
        final rightIndex = order.indexOf(right.provider);
        final byProvider = (leftIndex < 0 ? order.length : leftIndex).compareTo(
          rightIndex < 0 ? order.length : rightIndex,
        );
        return byProvider != 0
            ? byProvider
            : left.displayName.compareTo(right.displayName);
      });
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          Text(
            'Updated ${_relativeTime(state.fetchedAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
          ),
          const SizedBox(height: AleraTokens.spaceMd),
          if (snapshots.isEmpty)
            const _EmptyQuotas()
          else
            for (final snapshot in snapshots) ...<Widget>[
              _QuotaCard(hostId: hostId, snapshot: snapshot),
              const SizedBox(height: AleraTokens.spaceMd),
            ],
        ],
      ),
    );
  }
}

class _QuotaCard extends ConsumerStatefulWidget {
  const _QuotaCard({required this.hostId, required this.snapshot});

  final String hostId;
  final QuotaSnapshot snapshot;

  @override
  ConsumerState<_QuotaCard> createState() => _QuotaCardState();
}

class _QuotaCardState extends ConsumerState<_QuotaCard> {
  var _tryingTui = false;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final meters = <QuotaMeter>[...snapshot.windows, ...snapshot.buckets];
    final connection = ref.watch(
      hostConnectionControllerProvider(widget.hostId),
    );
    final supportsClaudeTui =
        connection.asData?.value.supportsAgentQuotaClaudeTui ?? false;
    final showTryTui =
        supportsClaudeTui &&
        snapshot.provider == 'claude' &&
        snapshot.status != 'ok';
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: AleraTokens.spaceLg,
                  backgroundColor: AleraTokens.surfaceVariant,
                  child: Text(
                    (quotaProviderLabels[snapshot.provider] ??
                            snapshot.provider)
                        .characters
                        .first
                        .toUpperCase(),
                  ),
                ),
                const SizedBox(width: AleraTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        quotaProviderLabels[snapshot.provider] ??
                            snapshot.provider,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        snapshot.displayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: snapshot.status),
              ],
            ),
            if (meters.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceLg),
              for (final meter in meters) ...<Widget>[
                _QuotaMeterRow(meter: meter),
                const SizedBox(height: AleraTokens.spaceMd),
              ],
            ],
            if (snapshot.error case final error?)
              Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: snapshot.status == 'stale'
                      ? AleraTokens.warning
                      : AleraTokens.error,
                ),
              ),
            if (showTryTui) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceMd),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _tryingTui
                      ? null
                      : () async {
                          setState(() => _tryingTui = true);
                          try {
                            await ref
                                .read(
                                  agentQuotaControllerProvider(
                                    widget.hostId,
                                  ).notifier,
                                )
                                .tryClaudeWithTui(snapshot);
                          } finally {
                            if (mounted) {
                              setState(() => _tryingTui = false);
                            }
                          }
                        },
                  child: Text(
                    _tryingTui ? 'Trying With TUI...' : 'Try With TUI',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuotaMeterRow extends StatelessWidget {
  const _QuotaMeterRow({required this.meter});

  final QuotaMeter meter;

  @override
  Widget build(BuildContext context) {
    final remaining = meter.remainingPercent;
    final color = remaining <= 10
        ? AleraTokens.error
        : remaining <= 25
        ? AleraTokens.warning
        : AleraTokens.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(meter.label)),
            Text('${remaining.toStringAsFixed(0)}% Remaining'),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          child: LinearProgressIndicator(
            value: remaining / 100,
            minHeight: AleraTokens.spaceSm,
            color: color,
            backgroundColor: AleraTokens.surfaceVariant,
          ),
        ),
        if (_resetLabel(meter) case final label?) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXs),
          Text(
            label,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'ok' => AleraTokens.success,
      'stale' => AleraTokens.warning,
      _ => AleraTokens.error,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.spaceSm,
        vertical: AleraTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AleraTokens.emphasisOverlayAlpha),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      ),
      child: Text(
        status == 'ok'
            ? 'Live'
            : status == 'stale'
            ? 'Stale'
            : 'Unavailable',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _EmptyQuotas extends StatelessWidget {
  const _EmptyQuotas();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Text('No Quota Providers Are Enabled.'),
      ),
    );
  }
}

class _QuotaError extends ConsumerWidget {
  const _QuotaError({required this.error, required this.hostId});

  final Object error;
  final String hostId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton(
              onPressed: ref
                  .read(agentQuotaControllerProvider(hostId).notifier)
                  .refresh,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _resetLabel(QuotaMeter meter) {
  final reset = meter.resetsAt;
  if (reset == null) return meter.resetDescription;
  final remaining = reset.difference(DateTime.now().toUtc());
  if (remaining.isNegative) return 'Reset Due';
  final days = remaining.inDays;
  final hours = remaining.inHours.remainder(24);
  final minutes = remaining.inMinutes.remainder(60);
  return 'Resets In ${days > 0 ? '${days}d ' : ''}${hours}h ${minutes}m';
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().toUtc().difference(value);
  if (difference.inSeconds < 60) return 'Just Now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m Ago';
  return '${difference.inHours}h Ago';
}
