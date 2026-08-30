import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/application/quota_host_visibility_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quota_provider_icon.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quotas_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_display_labels.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_ordering.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_hosts_settings_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_status_pill.dart';
import 'package:alera_mobile/src/features/settings/application/host_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact per-host quota summaries for the Home screen.
class HomeQuotasSection extends ConsumerWidget {
  const HomeQuotasSection({super.key, required this.hosts});

  final List<PairedHostProfile> hosts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(quotaHostVisibilityControllerProvider);
    final hidden = visibility.value;
    // Wait for the local selection before subscribing to any host's quotas.
    final visibleHosts = hidden == null
        ? const <PairedHostProfile>[]
        : hosts.where((host) => !hidden.contains(host.runtimeId)).toList();
    final groupByHost = hosts.length > 1;
    final children = <Widget>[];

    for (final host in visibleHosts) {
      final async = ref.watch(agentQuotaControllerProvider(host.id));
      final settings = ref
          .watch(hostSettingsControllerProvider(host.id))
          .value
          ?.agentQuotas;
      final hostChildren = _hostQuotaChildren(
        context: context,
        ref: ref,
        host: host,
        async: async,
        settings: settings,
        showHostHeading: groupByHost,
      );
      children.addAll(hostChildren);
    }

    if (hosts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AleraTokens.spaceLg),
        AleraSectionHeader(
          label: 'Quotas',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const QuotaHostsSettingsScreen(),
              ),
            ),
            child: const Text('Choose Hosts'),
          ),
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            right: AleraTokens.space8,
            top: AleraTokens.space8,
            bottom: AleraTokens.space4,
          ),
        ),
        if (visibility.hasError)
          AleraEmptyState(
            message: 'Could not load quota hosts.',
            action: TextButton(
              onPressed: () =>
                  ref.invalidate(quotaHostVisibilityControllerProvider),
              child: const Text('Retry'),
            ),
          )
        else if (hidden != null && visibleHosts.isEmpty)
          const AleraEmptyState(
            message:
                'No hosts selected. Choose hosts to show their quotas here.',
          ),
        ...children,
      ],
    );
  }

  List<Widget> _hostQuotaChildren({
    required BuildContext context,
    required WidgetRef ref,
    required PairedHostProfile host,
    required AsyncValue<QuotaSnapshotState> async,
    required QuotaSettings? settings,
    required bool showHostHeading,
  }) {
    if (async.hasError && async.value == null) {
      final error = async.error!;
      if (error is UnsupportedError) {
        return const <Widget>[];
      }
      return <Widget>[
        if (showHostHeading)
          Padding(
            padding: const EdgeInsets.only(
              top: AleraTokens.spaceMd,
              bottom: AleraTokens.spaceSm,
            ),
            child: Text(
              host.effectiveName,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        _HomeQuotaErrorCard(
          message: error.toString(),
          onRetry: () => ref
              .read(agentQuotaControllerProvider(host.id).notifier)
              .refresh(),
          onOpen: () => _openQuotas(context, host),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
      ];
    }

    final state = async.value;
    if (state == null || state.snapshots.isEmpty) {
      return const <Widget>[];
    }

    final snapshots = sortedQuotaSnapshots(state.snapshots, settings: settings);

    return <Widget>[
      if (showHostHeading)
        Padding(
          padding: const EdgeInsets.only(
            top: AleraTokens.spaceMd,
            bottom: AleraTokens.spaceSm,
          ),
          child: Text(
            host.effectiveName,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      for (final snapshot in snapshots) ...<Widget>[
        _HomeQuotaCard(
          snapshot: snapshot,
          onTap: () => _openQuotas(context, host),
        ),
        const SizedBox(height: AleraTokens.spaceMd),
      ],
    ];
  }

  void _openQuotas(BuildContext context, PairedHostProfile host) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => AgentQuotasScreen(host: host)),
    );
  }
}

class _HomeQuotaCard extends StatelessWidget {
  const _HomeQuotaCard({required this.snapshot, required this.onTap});

  final QuotaSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meters = sortedQuotaMeters(snapshot);
    final title = quotaSnapshotTitle(
      provider: snapshot.provider,
      accountId: snapshot.accountId,
      displayName: snapshot.displayName,
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: onTap,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  AgentQuotaProviderIcon(provider: snapshot.provider),
                  const SizedBox(width: AleraTokens.spaceMd),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  QuotaStatusPill(status: snapshot.status),
                ],
              ),
              if (meters.isNotEmpty) ...<Widget>[
                const SizedBox(height: AleraTokens.spaceMd),
                for (var index = 0; index < meters.length; index++) ...<Widget>[
                  _HomeQuotaMeterRow(
                    provider: snapshot.provider,
                    meter: meters[index],
                  ),
                  if (index < meters.length - 1)
                    const SizedBox(height: AleraTokens.spaceMd),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeQuotaMeterRow extends StatelessWidget {
  const _HomeQuotaMeterRow({required this.provider, required this.meter});

  final String provider;
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
            Expanded(
              child: Text(
                quotaMeterDisplayLabel(provider, meter.label),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              meter.displayValue ??
                  '${remaining.toStringAsFixed(0)}% Remaining',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        if (meter.displayValue == null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: LinearProgressIndicator(
              value: remaining / 100,
              minHeight: AleraTokens.spaceSm,
              color: color,
              backgroundColor: AleraTokens.surfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _HomeQuotaErrorCard extends StatelessWidget {
  const _HomeQuotaErrorCard({
    required this.message,
    required this.onRetry,
    required this.onOpen,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Row(
              children: <Widget>[
                TextButton(onPressed: onRetry, child: const Text('Retry')),
                TextButton(onPressed: onOpen, child: const Text('Open Quotas')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
