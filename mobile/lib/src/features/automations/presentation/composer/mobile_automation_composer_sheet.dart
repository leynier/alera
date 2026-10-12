import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// A composer property edited in a bottom sheet. Edits apply as they are
/// made; Done only closes the sheet.
Future<void> showMobileAutomationComposerSheet(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, VoidCallback close) builder,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheetContext) {
    void close() => Navigator.of(sheetContext).pop();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.spaceLg,
              AleraTokens.spaceSm,
              AleraTokens.spaceSm,
              0,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(onPressed: close, child: const Text('Done')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: controller,
              padding: EdgeInsets.fromLTRB(
                AleraTokens.spaceLg,
                AleraTokens.spaceSm,
                AleraTokens.spaceLg,
                AleraTokens.spaceLg + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: builder(context, close),
            ),
          ),
        ],
      ),
    );
  },
);

/// One tappable property of the composer: what it is, its current value,
/// whether context chose it, and the problem it has, if any.
class const MobileAutomationPropertyRow({
  required final IconData icon,
  required final String label,
  required final String value,
  final VoidCallback? onTap,
  final String? problem,
  final bool fromContext = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = this.problem;
    final color = problem == null
        ? AleraTokens.foregroundMuted
        : AleraTokens.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: AleraTokens.minTapTarget,
      leading: Icon(icon, size: AleraTokens.iconMd, color: color),
      title: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: color),
      ),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
            ),
          ),
          if (problem != null)
            Text(
              problem,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
        ],
      ),
      trailing: fromContext
          ? const AleraBadge(label: 'From Context')
          : onTap == null
          ? null
          : const Icon(
              AleraIcons.chevronRight,
              size: AleraTokens.iconMd,
              color: AleraTokens.foregroundMuted,
            ),
      onTap: onTap,
    );
  }
}
