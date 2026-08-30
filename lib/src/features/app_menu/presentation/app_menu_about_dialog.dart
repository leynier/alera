import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// About dialog: app logo, copyable version line, and an update check action.
class const AppMenuAboutDialog({
  super.key,
  required final PackageInfo info,
  required final VoidCallback onCheckForUpdates,
}) extends StatelessWidget {
  String get _versionLabel => '${info.version} (${info.buildNumber})';

  Future<void> _copyVersion(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _versionLabel));
    if (context.mounted) {
      AleraToast.show(context, message: 'Version copied');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 400,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space12,
          AleraTokens.space16,
          AleraTokens.space16,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'About $kAleraAppName',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Center(
              child: Image.asset(
                'assets/logo/alera-logo-white.png',
                width: 64,
                height: 64,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Center(
              child: Text(kAleraAppName, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: AleraTokens.space4),
            Row(
              mainAxisAlignment: .center,
              children: <Widget>[
                Text(
                  'Version $_versionLabel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Copy Version',
                  icon: AleraIcons.copy,
                  iconSize: 14,
                  minSize: 24,
                  onPressed: () => _copyVersion(context),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space20),
            OverflowBar(
              alignment: .end,
              spacing: AleraTokens.space8,
              overflowSpacing: AleraTokens.space8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: onCheckForUpdates,
                  child: const Text('Check For Updates'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
