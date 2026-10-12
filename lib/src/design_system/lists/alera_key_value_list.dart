import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One labelled value of an [AleraKeyValueList]. [mono] sets the value in the
/// monospaced face (ids, paths, hashes); [copyable] adds a Copy button.
class const AleraKeyValue({
  required final String label,
  required final String value,
  final bool mono = false,
  final bool copyable = false,
  final Widget? trailing,
});

/// Two-column list of labelled facts. Values are selectable and wrap instead
/// of clipping; under [AleraTokens.keyValueStackBreakpoint] each label sits
/// above its value so a narrow panel keeps the value readable.
class const AleraKeyValueList({
  super.key,
  required final List<AleraKeyValue> entries,
  final double? labelWidth,
  final ValueChanged<AleraKeyValue>? onCopied,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < AleraTokens.keyValueStackBreakpoint;
        return Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            for (final entry in entries)
              _AleraKeyValueRow(
                entry: entry,
                stacked: stacked,
                labelWidth: labelWidth ?? AleraTokens.keyValueListLabelWidth,
                onCopied: onCopied,
              ),
          ],
        );
      },
    );
  }
}

class const _AleraKeyValueRow({
  required final AleraKeyValue entry,
  required final bool stacked,
  required final double labelWidth,
  required final ValueChanged<AleraKeyValue>? onCopied,
}) extends StatelessWidget {
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: entry.value));
    onCopied?.call(entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      entry.label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: AleraTokens.foregroundMuted,
      ),
    );
    final trailing = entry.trailing;
    final value = Row(
      crossAxisAlignment: .start,
      children: <Widget>[
        Expanded(
          child: SelectableText(
            entry.value,
            style: entry.mono
                ? AleraTokens.monoCompactStyle.copyWith(
                    color: AleraTokens.foreground,
                  )
                : theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foreground,
                  ),
          ),
        ),
        if (entry.copyable) ...<Widget>[
          const SizedBox(width: AleraTokens.space4),
          AleraIconButton(
            key: ValueKey<String>('keyValueCopy:${entry.label}'),
            tooltip: 'Copy',
            icon: AleraIcons.copy,
            iconSize: AleraTokens.iconSm,
            minSize: AleraTokens.iconButtonXs,
            borderRadius: AleraTokens.radiusXs,
            onPressed: _copy,
          ),
        ],
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AleraTokens.space4),
          trailing,
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: stacked
          ? Column(
              crossAxisAlignment: .stretch,
              mainAxisSize: .min,
              children: <Widget>[
                label,
                const SizedBox(height: AleraTokens.space2),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                SizedBox(width: labelWidth, child: label),
                const SizedBox(width: AleraTokens.space12),
                Expanded(child: value),
              ],
            ),
    );
  }
}
