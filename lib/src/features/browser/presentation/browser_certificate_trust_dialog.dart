import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:flutter/material.dart';

enum BrowserCertificateTrustChoice { cancel, session, permanent }

class const BrowserCertificateTrustDialog({
  super.key,
  required final BrowserTlsRequest request,
  required final String profileLabel,
  required final bool canPersist,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
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
              'This certificate uses a private or self-signed issuer. Trust applies to ${request.host} on every port and tab in $profileLabel.',
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
                contextMenuBuilder: AleraTextSelectionToolbar.editableText,
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
                    onPressed: () => _finish(context, .cancel),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _finish(context, .session),
                    child: const Text('Trust For This Session'),
                  ),
                ),
                if (canPersist) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _finish(context, .permanent),
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

class const _CertificateDetail({
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
