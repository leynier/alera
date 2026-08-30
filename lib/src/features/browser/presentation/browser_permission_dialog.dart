import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:flutter/material.dart';

final class const BrowserPermissionPromptResult({
  required final BrowserPermissionDecision decision,
  required final bool rememberForProfile,
});

class const BrowserPermissionDialog({
  super.key,
  required final BrowserPermissionRequest request,
  required final String profileLabel,
}) extends StatefulWidget {
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
          mainAxisSize: .min,
          crossAxisAlignment: .start,
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
                  ? '${request.origin} requested ${_permissionLabel(request.permission)}, which Alera does not allow.'
                  : '${request.origin} wants to use ${_permissionLabel(request.permission)}.',
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
                    onPressed: () => _finish(.deny),
                    child: const Text('Deny'),
                  ),
                ),
                if (!denyOnly) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _finish(.allow),
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
    BrowserPermissionType.geolocation => 'your location',
    BrowserPermissionType.camera => 'your camera',
    BrowserPermissionType.microphone => 'your microphone',
    BrowserPermissionType.notifications => 'Notifications',
    BrowserPermissionType.clipboardRead => 'clipboard reading',
    BrowserPermissionType.clipboardWrite => 'clipboard writing',
    BrowserPermissionType.fullscreen => 'full screen',
    BrowserPermissionType.persistentStorage => 'persistent storage',
    BrowserPermissionType.pointerLock => 'pointer lock',
    BrowserPermissionType.webAuthn => 'a security key',
    BrowserPermissionType.displayCapture => 'screen capture',
    BrowserPermissionType.unknown => 'an unsupported permission',
  };
}
