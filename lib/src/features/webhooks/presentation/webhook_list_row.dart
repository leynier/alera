import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_device_list_row.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:flutter/material.dart';

/// One webhook: its URL and status, the events it receives, its last delivery,
/// and Test and Delete actions.
class const WebhookListRow({
  super.key,
  required final RuntimeWebhook webhook,
  required final VoidCallback onTest,
  required final VoidCallback onDelete,
  final bool busy = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedSmall = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final status = webhookStatusBadge(webhook.status);
    final lastError = webhook.lastError;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.link,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Wrap(
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space4,
                  crossAxisAlignment: .center,
                  children: <Widget>[
                    Text(
                      webhook.url,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: AleraTokens.monoStyle.copyWith(
                        color: AleraTokens.foreground,
                      ),
                    ),
                    ?status,
                    AleraChip(
                      label: webhookKindsSummary(webhook),
                      tooltip: _kindsTooltip(webhook),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  webhookDeliveryDetail(webhook),
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: mutedSmall,
                ),
                if (lastError != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    'Last error: $lastError',
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          AleraIconButton(
            tooltip: 'Send Test Event',
            icon: AleraIcons.send,
            onPressed: busy ? null : onTest,
          ),
          AleraIconButton(
            tooltip: 'Delete Webhook',
            icon: AleraIcons.delete,
            iconColor: AleraTokens.error,
            onPressed: busy ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

/// Short description of the events a webhook receives.
String webhookKindsSummary(RuntimeWebhook webhook) {
  if (webhook.receivesAllKinds) {
    return 'All Events';
  }
  final labels = _kindLabels(webhook);
  return switch (labels.length) {
    0 => 'No Events',
    1 || 2 => labels.join(', '),
    final count => '$count Events',
  };
}

/// When the webhook last delivered, and when it was added.
String webhookDeliveryDetail(RuntimeWebhook webhook) {
  final lastDelivery = webhook.lastDeliveryAt;
  final createdAt = webhook.createdAt;
  return <String>[
    lastDelivery == null
        ? 'No deliveries yet'
        : 'Last delivery ${formatMobileTimestamp(lastDelivery)}',
    if (createdAt != null) 'Added ${formatMobileTimestamp(createdAt)}',
    if (!webhook.allRuntimes)
      switch (webhook.runtimeIds.length) {
        1 => '1 runtime',
        final count => '$count runtimes',
      },
  ].join(' · ');
}

/// Badge for the cloud's delivery status, or `null` when it reports none.
AleraBadge? webhookStatusBadge(String status) {
  final normalized = status.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  final tone = switch (normalized) {
    'active' || 'enabled' || 'healthy' || 'ok' => AleraBadgeTone.success,
    'failing' || 'failed' || 'error' || 'blocked' => AleraBadgeTone.error,
    'pending' || 'retrying' => AleraBadgeTone.attention,
    _ => AleraBadgeTone.neutral,
  };
  return AleraBadge(label: _titleCase(normalized), tone: tone);
}

List<String> _kindLabels(RuntimeWebhook webhook) {
  return <String>[
    for (final kind in webhook.kinds)
      RuntimeEventKind.fromWire(kind)?.label ?? kind,
  ];
}

String _kindsTooltip(RuntimeWebhook webhook) {
  if (webhook.kinds.isEmpty) {
    return '';
  }
  return webhook.kinds.join('\n');
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'[\s_-]+'))
      .where((word) => word.isNotEmpty)
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
