import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_device.dart';
import 'package:flutter/material.dart';

class MobileDeviceListRow extends StatelessWidget {
  const MobileDeviceListRow({
    super.key,
    required this.device,
    required this.onRename,
    required this.onRevoke,
    required this.onDelete,
  });

  final MobileDevice device;
  final VoidCallback? onRename;
  final VoidCallback? onRevoke;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastSeen = device.lastSeenAt;
    final detail = device.isRevoked
        ? 'Revoked ${formatMobileTimestamp(device.revokedAt!)}'
        : lastSeen == null
        ? 'Paired ${formatMobileTimestamp(device.pairedAt)}'
        : 'Last Seen ${formatMobileTimestamp(lastSeen)}';
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Icon(
            AleraIcons.mobileDevice,
            size: 16,
            color: device.isRevoked
                ? AleraTokens.foregroundFaint
                : AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        device.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: device.isRevoked
                              ? AleraTokens.foregroundMuted
                              : AleraTokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (device.isRevoked) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      const AleraBadge(
                        label: 'Revoked',
                        color: AleraTokens.error,
                        foregroundColor: AleraTokens.onError,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ),
          ),
          if (device.isRevoked)
            AleraIconButton(
              tooltip: 'Delete Device',
              icon: AleraIcons.delete,
              iconColor: AleraTokens.error,
              onPressed: onDelete,
            )
          else ...<Widget>[
            AleraIconButton(
              tooltip: 'Rename Device',
              icon: AleraIcons.edit,
              onPressed: onRename,
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Revoke Device',
              icon: AleraIcons.delete,
              iconColor: AleraTokens.error,
              onPressed: onRevoke,
            ),
          ],
        ],
      ),
    );
  }
}

String formatMobileTimestamp(DateTime value) {
  final local = value.toLocal();
  final date =
      '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}
