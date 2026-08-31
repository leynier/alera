import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:flutter/material.dart';

class const KeepAliveStatusChip({
  super.key,
  required final KeepAliveSnapshot snapshot,
  required final bool enabled,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = _chipColor(snapshot, enabled: enabled);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Tooltip(
          message: _tooltip(snapshot, enabled: enabled),
          child: Semantics(
            button: true,
            toggled: snapshot.active,
            label: 'Keep Alive',
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
                  Icon(AleraIcons.keepAlive, size: 13, color: color),
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    'Keep Alive',
                    style: AleraTokens.monoStyle.copyWith(
                      fontSize: 10,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _chipColor(KeepAliveSnapshot snapshot, {required bool enabled}) {
  if (snapshot.hasError && !snapshot.active) {
    return AleraTokens.warning;
  }
  if (snapshot.active || enabled) {
    return AleraTokens.success;
  }
  return AleraTokens.foregroundMuted;
}

String _tooltip(KeepAliveSnapshot snapshot, {required bool enabled}) {
  if (snapshot.hasError && !snapshot.active) {
    return snapshot.error!.trim();
  }
  if (snapshot.active || enabled) {
    return 'Keeping this computer and display awake';
  }
  return 'Keep this computer and display awake';
}
