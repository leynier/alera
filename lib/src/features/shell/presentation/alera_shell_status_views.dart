import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/icons/alera_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown while the local database opens, before any workbench state exists.
class const AleraShellLoadingView({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AleraTokens.bg,
      body: Center(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            const AleraLogo(),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisSize: .min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: AleraTokens.iconSm,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeThin,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Text(
                  'Opening Alera…',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the local database cannot open. The details stay selectable and
/// copyable so they can be pasted into a bug report.
class const AleraShellDatabaseErrorView({
  super.key,
  required final String error,
}) extends StatefulWidget {
  @override
  State<AleraShellDatabaseErrorView> createState() =>
      _AleraShellDatabaseErrorViewState();
}

class _AleraShellDatabaseErrorViewState
    extends State<AleraShellDatabaseErrorView> {
  bool _copied = false;

  Future<void> _copyDetails() async {
    await Clipboard.setData(ClipboardData(text: widget.error));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AleraTokens.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AleraTokens.emptyStateMaxWidth,
            ),
            child: Column(
              mainAxisSize: .min,
              children: <Widget>[
                const Icon(
                  AleraIcons.error,
                  size: AleraTokens.iconEmptyState,
                  color: AleraTokens.error,
                ),
                const SizedBox(height: AleraTokens.space12),
                Text(
                  'Failed to open the local database',
                  textAlign: .center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AleraTokens.space8),
                Text(
                  'Alera keeps your projects and workspaces in this database. '
                  'Copy the details below when you report the problem.',
                  textAlign: .center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(height: AleraTokens.space16),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(
                    maxHeight: AleraTokens.activityLogHeight,
                  ),
                  decoration: BoxDecoration(
                    color: AleraTokens.surface,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    border: Border.all(color: AleraTokens.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AleraTokens.space12),
                    child: SelectableText(
                      widget.error,
                      style: AleraTokens.monoCompactStyle,
                    ),
                  ),
                ),
                const SizedBox(height: AleraTokens.space16),
                OutlinedButton.icon(
                  onPressed: _copyDetails,
                  icon: Icon(
                    _copied ? AleraIcons.check : AleraIcons.copy,
                    size: AleraTokens.iconMd,
                  ),
                  label: Text(_copied ? 'Copied' : 'Copy Details'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
