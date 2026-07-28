import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter/material.dart';

class BrowserSecurityDialog extends StatelessWidget {
  const BrowserSecurityDialog({
    super.key,
    required this.security,
    this.onTrustLocalCertificate,
  });

  final BrowserSecurityState security;
  final VoidCallback? onTrustLocalCertificate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = security.challenge;
    return AleraDialog(
      maxWidth: AleraTokens.sidebarMaxWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              security.origin ?? 'No Origin Is Available',
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
                width: double.infinity,
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

class _SecurityDetail extends StatelessWidget {
  const _SecurityDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
    BrowserSecurityLevel.secure => 'Secure Connection',
    BrowserSecurityLevel.local => 'Local Connection',
    BrowserSecurityLevel.insecure => 'Insecure Connection',
    BrowserSecurityLevel.certificateFailure => 'Certificate Failure',
    BrowserSecurityLevel.unknown => 'Connection Details',
  };
}

String _description(BrowserSecurityLevel level) {
  return switch (level) {
    BrowserSecurityLevel.secure =>
      'The Page Is Using An Encrypted HTTPS Connection.',
    BrowserSecurityLevel.local =>
      'The Page Is Served From A Local Host. Certificate Trust Is Scoped To The Active Browser Profile.',
    BrowserSecurityLevel.insecure =>
      'The Page Is Not Using An Encrypted Connection. Do Not Enter Sensitive Information.',
    BrowserSecurityLevel.certificateFailure =>
      'Alera Rejected The Certificate. Public Hosts Cannot Bypass Certificate Failures.',
    BrowserSecurityLevel.unknown =>
      'Connection Security Has Not Been Established Yet.',
  };
}
