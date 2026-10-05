import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_value_format.dart';
import 'package:flutter/material.dart';

/// Status-bar chip: total memory plus the running session count, with the
/// orphan count called out when there is one.
class const ResourceStatusChip({
  super.key,
  required final ResourceSnapshot snapshot,
  required final int sessionCount,
  required final int orphanCount,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final memory = snapshot.hasReading
        ? formatResourceMemory(snapshot.totalMemoryBytes)
        : resourceAbsentReading;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        // Every clickable chip in the status bar uses the hand cursor; the
        // InkWell default stays an arrow off the web.
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Tooltip(
          message: 'Resource Manager',
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: _semanticsLabel(memory),
            excludeSemantics: true,
            child: Container(
              height: AleraTokens.statusBarHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
              ),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AleraTokens.borderSubtle),
                ),
              ),
              child: Row(
                mainAxisSize: .min,
                children: <Widget>[
                  const Icon(
                    AleraIcons.resources,
                    size: AleraTokens.iconStatusBar,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Text(memory, style: AleraTokens.statusBarTextStyle),
                  const SizedBox(width: AleraTokens.space6),
                  const Icon(
                    AleraIcons.terminal,
                    size: AleraTokens.iconStatusBarSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  Text('$sessionCount', style: AleraTokens.statusBarTextStyle),
                  if (orphanCount > 0) ...<Widget>[
                    const SizedBox(width: AleraTokens.space4),
                    Text(
                      '($orphanCount)',
                      style: AleraTokens.statusBarTextStyle.copyWith(
                        color: AleraTokens.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticsLabel(String memory) {
    final sessions = sessionCount == 1 ? '1 session' : '$sessionCount sessions';
    final orphans = orphanCount > 0 ? ', $orphanCount orphaned' : '';
    return 'Resource Manager, memory $memory, $sessions$orphans';
  }
}
