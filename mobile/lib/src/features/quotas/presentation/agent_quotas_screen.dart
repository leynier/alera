import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quota_provider_icon.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_display_labels.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_ordering.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_settings_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_status_pill.dart';
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
    final snapshots = sortedQuotaSnapshots(state.snapshots, settings: settings);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          Text(
            'Updated ${_relativeTime(state.fetchedAt)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
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
  var _usingReset = false;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _scheduleExpiryRefresh();
  }

  @override
  void didUpdateWidget(covariant _QuotaCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.rateLimitResetCredits?.nextExpiresAt !=
        widget.snapshot.rateLimitResetCredits?.nextExpiresAt) {
      _scheduleExpiryRefresh();
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scheduleExpiryRefresh() {
    _expiryTimer?.cancel();
    final expiry = widget.snapshot.rateLimitResetCredits?.nextExpiresAt;
    if (expiry == null) return;
    final remaining = expiry.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return;
    final interval = remaining > const Duration(days: 1)
        ? const Duration(hours: 1)
        : const Duration(minutes: 1);
    _expiryTimer = Timer(interval, () {
      if (!mounted) return;
      setState(() {});
      _scheduleExpiryRefresh();
    });
  }

  Future<void> _useCodexReset() async {
    final credits = widget.snapshot.rateLimitResetCredits;
    if (_usingReset || credits == null || !credits.canConsume) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Use Codex Reset'),
            content: const Text(
              'Use one Codex rate-limit reset credit? Alera will re-check the active account and offer before applying it.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Use Reset'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _usingReset = true);
    try {
      final result = await ref
          .read(agentQuotaControllerProvider(widget.hostId).notifier)
          .consumeCodexResetCredit(widget.snapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_codexResetMessage(result))));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Codex reset failed: $error')));
    } finally {
      if (mounted) setState(() => _usingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final meters = sortedQuotaMeters(snapshot);
    final connection = ref.watch(
      hostConnectionControllerProvider(widget.hostId),
    );
    final supportsClaudeTui =
        connection.asData?.value.supportsAgentQuotaClaudeTui ?? false;
    final supportsCodexResets =
        connection.asData?.value.supportsCodexResetCredits ?? false;
    final showTryTui =
        supportsClaudeTui &&
        snapshot.provider == 'claude' &&
        snapshot.status != 'ok';
    final resetCredits = snapshot.provider == 'codex'
        ? snapshot.rateLimitResetCredits
        : null;
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                AgentQuotaProviderIcon(provider: snapshot.provider, size: 22),
                const SizedBox(width: AleraTokens.spaceMd),
                Expanded(
                  child: Text(
                    quotaSnapshotTitle(
                      provider: snapshot.provider,
                      accountId: snapshot.accountId,
                      displayName: snapshot.displayName,
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                QuotaStatusPill(status: snapshot.status),
              ],
            ),
            if (meters.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceLg),
              for (final meter in meters) ...<Widget>[
                _QuotaMeterRow(provider: snapshot.provider, meter: meter),
                const SizedBox(height: AleraTokens.spaceMd),
              ],
            ],
            if (snapshot.error case final error?)
              Text(
                normalizeQuotaText(error),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: snapshot.status == 'stale'
                      ? AleraTokens.warning
                      : AleraTokens.error,
                ),
              ),
            if (resetCredits case final credits?) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceMd),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${credits.availableCount} Rate-Limit ${credits.availableCount == 1 ? 'Reset' : 'Resets'} Available',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        if (_codexResetExpiryText(credits.nextExpiresAt)
                            case final expiry?)
                          Text(
                            expiry,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          ),
                      ],
                    ),
                  ),
                  if (credits.availableCount > 0)
                    TextButton(
                      onPressed:
                          supportsCodexResets &&
                              credits.canConsume &&
                              !_usingReset
                          ? _useCodexReset
                          : null,
                      child: Text(_usingReset ? 'Applying...' : 'Use Reset'),
                    ),
                ],
              ),
            ],
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
                                  agentQuotaControllerProvider(widget.hostId)
                                      .notifier,
                                )
                                .tryClaudeWithTui(snapshot);
                          } finally {
                            if (mounted) {
                              setState(() => _tryingTui = false);
                            }
                          }
                        },
                  child: Text(
                    _tryingTui ? 'Trying with TUI...' : 'Try With TUI',
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

String _codexResetMessage(CodexResetConsumeResult result) {
  if (result.status == 'rejected') {
    return result.reason == 'offerChanged'
        ? 'Codex reset offer changed. Review the updated credits.'
        : 'No Codex reset credit is available.';
  }
  return switch (result.outcome) {
    'reset' => 'Codex rate limit reset applied.',
    'nothingToReset' => 'Codex has no active rate limit to reset.',
    'noCredit' => 'No Codex reset credit is available.',
    'alreadyRedeemed' => 'This Codex reset was already applied.',
    _ => 'Codex reset result was unavailable.',
  };
}

String? _codexResetExpiryText(DateTime? expiry) {
  if (expiry == null) return null;
  final remaining = expiry.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) return 'Next reset expired';
  if (remaining.inDays > 0) {
    return 'Next reset expires in ${remaining.inDays}d ${remaining.inHours % 24}h';
  }
  if (remaining.inHours > 0) {
    return 'Next reset expires in ${remaining.inHours}h ${remaining.inMinutes % 60}m';
  }
  return 'Next reset expires in ${remaining.inMinutes.clamp(1, 59)}m';
}

class _QuotaMeterRow extends StatelessWidget {
  const _QuotaMeterRow({required this.provider, required this.meter});

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
              child: Text(quotaMeterDisplayLabel(provider, meter.label)),
            ),
            Text(
              meter.displayValue ??
                  '${remaining.toStringAsFixed(0)}% Remaining',
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
        if (_resetLabel(meter) case final label?) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXs),
          Text(
            label,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ],
      ],
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
        child: Text('No quota providers are enabled.'),
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
  if (remaining.isNegative) return 'Reset due';
  final days = remaining.inDays;
  final hours = remaining.inHours.remainder(24);
  final minutes = remaining.inMinutes.remainder(60);
  return 'Resets in ${days > 0 ? '${days}d ' : ''}${hours}h ${minutes}m';
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().toUtc().difference(value);
  if (difference.inSeconds < 60) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m Ago';
  return '${difference.inHours}h Ago';
}
