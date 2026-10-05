import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';

/// One Quick Open match: the file name emphasized, its directory dimmed after
/// it, so the name stays the first thing the eye lands on.
class const QuickOpenResultRow({
  super.key,
  required final String relativePath,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Workspace file paths come from the native index with either separator.
    final separator = relativePath.lastIndexOf(RegExp(r'[/\\]'));
    final name = relativePath.substring(separator + 1);
    final directory = separator < 0 ? '' : relativePath.substring(0, separator);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
      child: AleraActiveRail(
        active: selected,
        child: Material(
          color: selected ? AleraActiveRail.selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          clipBehavior: .antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  AleraFileIcon(
                    pathOrName: relativePath,
                    kind: .file,
                    size: AleraTokens.iconLg,
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                      ),
                    ),
                  ),
                  if (directory.isNotEmpty) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        directory,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the results when the workspace file index fails.
class const QuickOpenLoadError({super.key, required final Object error})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            const Icon(AleraIcons.error, color: AleraTokens.error),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'Could not load workspace files.',
              style: theme.textTheme.bodyMedium,
              textAlign: .center,
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              error.toString(),
              maxLines: 3,
              overflow: .ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              textAlign: .center,
            ),
          ],
        ),
      ),
    );
  }
}
