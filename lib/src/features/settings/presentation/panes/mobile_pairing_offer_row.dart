import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';
import 'package:flutter/material.dart';

class MobilePairingOfferRow extends StatelessWidget {
  const MobilePairingOfferRow({
    super.key,
    required this.offer,
    required this.onCancel,
  });

  final MobilePairingOffer offer;
  final VoidCallback? onCancel;

  String get _expiryLabel {
    final remaining = offer.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return 'Expired';
    }
    if (remaining.inMinutes >= 1) {
      return 'Expires In ${remaining.inMinutes}m';
    }
    return 'Expires In ${remaining.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceName = offer.expectedDeviceName;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.qrCode,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  deviceName == null || deviceName.isEmpty
                      ? offer.endpoint
                      : '$deviceName · ${offer.endpoint}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AleraTokens.space4),
                Text(
                  _expiryLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.warning,
                  ),
                ),
              ],
            ),
          ),
          AleraIconButton(
            tooltip: 'Cancel Offer',
            icon: AleraIcons.cancel,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
