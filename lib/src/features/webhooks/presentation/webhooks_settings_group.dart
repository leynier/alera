import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/presentation/webhook_list_row.dart';
import 'package:flutter/material.dart';

const double _kActionsControlWidth = 260;

/// What the Webhooks group currently holds.
sealed class WebhooksView {
  const WebhooksView();
}

/// The runtime does not serve `webhook.*`, or its capabilities are unknown.
final class const WebhooksUnavailable(final String message)
    extends WebhooksView;

final class const WebhooksSignedOut() extends WebhooksView;

final class const WebhooksLoading() extends WebhooksView;

final class const WebhooksFailed(final String message) extends WebhooksView;

final class const WebhooksLoaded(final List<RuntimeWebhook> webhooks)
    extends WebhooksView;

/// Signed webhooks that receive this account's runtime events. Presentational:
/// the settings wrapper loads the list and runs every action.
class const WebhooksSettingsGroup({
  super.key,
  required final WebhooksView view,
  required final VoidCallback onRefresh,
  required final VoidCallback onAdd,
  required final ValueChanged<RuntimeWebhook> onTest,
  required final ValueChanged<RuntimeWebhook> onDelete,
  final Set<String> busyIds = const <String>{},
  final String? error,
  final String? notice,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final view = this.view;
    final ready = view is WebhooksLoaded || view is WebhooksFailed;
    return AleraSettingsGroup(
      title: 'Webhooks',
      description:
          'Signed HTTPS callbacks for inbox replies, agent status, '
          'orchestration, automations, workspaces and pull request watches. '
          'Payloads carry ids and states only.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Event Webhooks',
          description:
              'Stored in your Alera account and delivered by the '
              'Alera cloud.',
          controlWidth: _kActionsControlWidth,
          child: Row(
            mainAxisAlignment: .end,
            children: <Widget>[
              AleraIconButton(
                tooltip: 'Refresh Webhooks',
                icon: AleraIcons.refresh,
                onPressed: ready ? onRefresh : null,
              ),
              const SizedBox(width: AleraTokens.space8),
              FilledButton.icon(
                onPressed: view is WebhooksLoaded ? onAdd : null,
                icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
                label: const Text('Add Webhook'),
              ),
            ],
          ),
        ),
        if (notice case final String message)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: AleraInlineNotice(message: message),
          ),
        if (error case final String message)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: AleraInlineNotice(tone: .error, message: message),
          ),
        ...switch (view) {
          WebhooksUnavailable(:final message) => <Widget>[
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: AleraInlineNotice(tone: .warning, message: message),
            ),
          ],
          WebhooksSignedOut() => const <Widget>[
            Padding(
              padding: EdgeInsets.all(AleraTokens.space12),
              child: AleraInlineNotice(
                tone: .warning,
                message:
                    'Sign in to an Alera account in Settings > Account to '
                    'manage webhooks.',
              ),
            ),
          ],
          WebhooksLoading() => const <Widget>[
            AleraEmptyState(loading: true, message: 'Loading webhooks…'),
          ],
          WebhooksFailed(:final message) => <Widget>[
            AleraEmptyState(
              icon: AleraIcons.error,
              title: 'Webhooks unavailable',
              message: message,
            ),
          ],
          WebhooksLoaded(:final webhooks) when webhooks.isEmpty =>
            const <Widget>[
              AleraEmptyState(
                icon: AleraIcons.link,
                title: 'No webhooks',
                message:
                    'Add a webhook to send runtime events to your own '
                    'service.',
              ),
            ],
          WebhooksLoaded(:final webhooks) => <Widget>[
            for (final webhook in webhooks)
              WebhookListRow(
                webhook: webhook,
                busy: busyIds.contains(webhook.id),
                onTest: () => onTest(webhook),
                onDelete: () => onDelete(webhook),
              ),
          ],
        },
      ],
    );
  }
}
