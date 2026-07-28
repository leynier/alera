import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:flutter/material.dart';

final class BrowserPermissionPromptResult {
  const BrowserPermissionPromptResult({
    required this.decision,
    required this.rememberForProfile,
  });

  final BrowserPermissionDecision decision;
  final bool rememberForProfile;
}

class BrowserPermissionDialog extends StatefulWidget {
  const BrowserPermissionDialog({
    super.key,
    required this.request,
    required this.profileLabel,
  });

  final BrowserPermissionRequest request;
  final String profileLabel;

  @override
  State<BrowserPermissionDialog> createState() =>
      _BrowserPermissionDialogState();
}

class _BrowserPermissionDialogState extends State<BrowserPermissionDialog> {
  bool _rememberForProfile = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final denyOnly =
        request.permission == BrowserPermissionType.displayCapture ||
        request.permission == BrowserPermissionType.unknown;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.secure,
                  size: AleraTokens.space20,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Browser Permission',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            Text(
              denyOnly
                  ? '${request.origin} Requested ${_permissionLabel(request.permission)}, Which Alera Does Not Allow.'
                  : '${request.origin} Wants To Use ${_permissionLabel(request.permission)}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (!denyOnly) ...<Widget>[
              const SizedBox(height: AleraTokens.space16),
              AleraCheckbox(
                value: _rememberForProfile,
                label: 'Remember For ${widget.profileLabel}',
                onChanged: (value) =>
                    setState(() => _rememberForProfile = value),
              ),
            ],
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _finish(BrowserPermissionDecision.deny),
                    child: const Text('Deny'),
                  ),
                ),
                if (!denyOnly) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _finish(BrowserPermissionDecision.allow),
                      child: const Text('Allow'),
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

  void _finish(BrowserPermissionDecision decision) {
    Navigator.of(context).pop(
      BrowserPermissionPromptResult(
        decision: decision,
        rememberForProfile: _rememberForProfile,
      ),
    );
  }
}

String _permissionLabel(BrowserPermissionType permission) {
  return switch (permission) {
    BrowserPermissionType.geolocation => 'Your Location',
    BrowserPermissionType.camera => 'Your Camera',
    BrowserPermissionType.microphone => 'Your Microphone',
    BrowserPermissionType.notifications => 'Notifications',
    BrowserPermissionType.clipboardRead => 'Clipboard Reading',
    BrowserPermissionType.clipboardWrite => 'Clipboard Writing',
    BrowserPermissionType.fullscreen => 'Full Screen',
    BrowserPermissionType.persistentStorage => 'Persistent Storage',
    BrowserPermissionType.pointerLock => 'Pointer Lock',
    BrowserPermissionType.webAuthn => 'A Security Key',
    BrowserPermissionType.displayCapture => 'Screen Capture',
    BrowserPermissionType.unknown => 'An Unsupported Permission',
  };
}
