import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter/material.dart';

class const BrowserSecurityDialog({
  super.key,
  required final BrowserSecurityState security,
  final VoidCallback? onTrustLocalCertificate,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = security.challenge;
    return AleraDialog(
      maxWidth: AleraTokens.sidebarMaxWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  security.isSecure ? AleraIcons.secure : AleraIcons.insecure,
                  color: security.isSecure
                      ? AleraTokens.success
                      : AleraTokens.warning,
                  size: AleraTokens.space20,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    _title(security.level),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AleraIcons.close),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              security.origin ?? 'No origin is available',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foreground,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              _description(security.level),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (challenge != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              _SecurityDetail(label: 'Host', value: challenge.host),
              _SecurityDetail(label: 'Error', value: challenge.errorCode),
              if (challenge.fingerprint case final fingerprint?)
                _SecurityDetail(label: 'Fingerprint', value: fingerprint),
            ],
            if (challenge?.canProceed == true &&
                onTrustLocalCertificate != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space20),
              SizedBox(
                width: .infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onTrustLocalCertificate!();
                  },
                  child: const Text('Review Certificate Trust'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class const _SecurityDetail({
  required final String label,
  required final String value,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Row(
        crossAxisAlignment: .start,
        children: <Widget>[
          SizedBox(
            width: AleraTokens.space48 * 2,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              contextMenuBuilder: AleraTextSelectionToolbar.editableText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foreground,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _title(BrowserSecurityLevel level) {
  return switch (level) {
    BrowserSecurityLevel.secure => 'Secure connection',
    BrowserSecurityLevel.local => 'Local connection',
    BrowserSecurityLevel.insecure => 'Insecure connection',
    BrowserSecurityLevel.certificateFailure => 'Certificate failure',
    BrowserSecurityLevel.unknown => 'Connection details',
  };
}

String _description(BrowserSecurityLevel level) {
  return switch (level) {
    BrowserSecurityLevel.secure =>
      'The page is using an encrypted HTTPS connection.',
    BrowserSecurityLevel.local => 'The page is served from a local host. Certificate trust is scoped to the active browser profile.',
    BrowserSecurityLevel.insecure => 'The page is not using an encrypted connection. Do not enter sensitive information.',
    BrowserSecurityLevel.certificateFailure => 'Alera rejected the certificate. Public hosts cannot bypass certificate failures.',
    BrowserSecurityLevel.unknown =>
      'Connection security has not been established yet.',
  };
}
