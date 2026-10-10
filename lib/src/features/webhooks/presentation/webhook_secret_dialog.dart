import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a new webhook's signing secret, which the cloud returns only once.
class const WebhookSecretDialog({
  super.key,
  required final RuntimeWebhookCreation creation,
}) extends StatefulWidget {
  @override
  State<WebhookSecretDialog> createState() => _WebhookSecretDialogState();
}

class _WebhookSecretDialogState extends State<WebhookSecretDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.creation.secret));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return AleraDialog(
      maxWidth: 520,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text('Webhook Added', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space8),
            Text(
              widget.creation.webhook.url,
              maxLines: 1,
              overflow: .ellipsis,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Text(
              'Signing Secret',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: .w500,
              ),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              'Use it to verify the signature header on each delivery.',
              style: muted,
            ),
            const SizedBox(height: AleraTokens.space8),
            Container(
              padding: const EdgeInsets.only(
                left: AleraTokens.space12,
                right: AleraTokens.space4,
              ),
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      widget.creation.secret,
                      maxLines: 1,
                      style: AleraTokens.monoStyle.copyWith(
                        color: AleraTokens.foreground,
                      ),
                    ),
                  ),
                  AleraIconButton(
                    tooltip: _copied ? 'Copied' : 'Copy Secret',
                    icon: _copied ? AleraIcons.check : AleraIcons.copy,
                    onPressed: _copy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            const AleraInlineNotice(
              tone: .warning,
              message:
                  "Copy this secret now. You won't see it again after you "
                  'close this dialog.',
            ),
            const SizedBox(height: AleraTokens.space20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
