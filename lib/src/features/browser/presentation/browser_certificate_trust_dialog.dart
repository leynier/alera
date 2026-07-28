import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:flutter/material.dart';

enum BrowserCertificateTrustChoice { cancel, session, permanent }

class BrowserCertificateTrustDialog extends StatelessWidget {
  const BrowserCertificateTrustDialog({
    super.key,
    required this.request,
    required this.profileLabel,
    required this.canPersist,
  });

  final BrowserTlsRequest request;
  final String profileLabel;
  final bool canPersist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.insecure,
                  color: AleraTokens.warning,
                  size: AleraTokens.space20,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Trust Local Certificate?',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              'This Certificate Uses A Private Or Self-Signed Issuer. Trust Applies To ${request.host} On Every Port And Tab In $profileLabel.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Container(
              padding: const EdgeInsets.all(AleraTokens.space12),
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                border: Border.all(color: AleraTokens.border),
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              ),
              child: SelectableText(
                displayBrowserCertificateFingerprint(request.fingerprintSha256),
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            _CertificateDetail(label: 'Host', value: request.host),
            _CertificateDetail(label: 'Profile', value: profileLabel),
            if (request.subject case final subject?)
              _CertificateDetail(label: 'Subject', value: subject),
            if (request.issuer case final issuer?)
              _CertificateDetail(label: 'Issuer', value: issuer),
            if (request.validFrom case final validFrom?)
              _CertificateDetail(
                label: 'Valid From',
                value: validFrom.toLocal().toString(),
              ),
            if (request.validTo case final validTo?)
              _CertificateDetail(
                label: 'Valid Until',
                value: validTo.toLocal().toString(),
              ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    autofocus: true,
                    onPressed: () =>
                        _finish(context, BrowserCertificateTrustChoice.cancel),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _finish(context, BrowserCertificateTrustChoice.session),
                    child: const Text('Trust For This Session'),
                  ),
                ),
                if (canPersist) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _finish(
                        context,
                        BrowserCertificateTrustChoice.permanent,
                      ),
                      child: const Text('Always Trust'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _finish(BuildContext context, BrowserCertificateTrustChoice choice) {
    Navigator.of(context).pop(choice);
  }
}

class _CertificateDetail extends StatelessWidget {
  const _CertificateDetail({required this.label, required this.value});

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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
