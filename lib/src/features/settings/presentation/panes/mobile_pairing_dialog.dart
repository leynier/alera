import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_qr_code.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/mobile_devices/domain/mobile_pairing_offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the one-time pairing payload as a QR plus copyable JSON. The pairing
/// secret cannot be recovered after this dialog closes; only cancel and
/// regenerate remain possible from the offers list.
class const MobilePairingDialog({
  super.key,
  required final MobilePairingOfferGrant grant,
  required final Future<void> Function() onCancelOffer,
}) extends StatefulWidget {
  @override
  State<MobilePairingDialog> createState() => _MobilePairingDialogState();
}

class _MobilePairingDialogState extends State<MobilePairingDialog> {
  Timer? _ticker;
  Duration _remaining = .zero;
  bool _copied = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _remaining = _timeLeft();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _timeLeft();
      setState(() => _remaining = remaining);
      if (remaining == Duration.zero) {
        _ticker?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _timeLeft() {
    final remaining = widget.grant.expiresAt.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _expired => _remaining == Duration.zero;

  Future<void> _copyPayload() async {
    await Clipboard.setData(ClipboardData(text: widget.grant.toQrJson()));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
  }

  Future<void> _cancelOffer() async {
    setState(() => _cancelling = true);
    try {
      await widget.onCancelOffer();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }

  String get _countdownLabel {
    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    return 'Expires in ${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Link Mobile Device',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Center(
              child: _expired
                  ? SizedBox(
                      width: 240,
                      height: 240,
                      child: Column(
                        mainAxisAlignment: .center,
                        children: <Widget>[
                          const Icon(
                            AleraIcons.qrCode,
                            size: 48,
                            color: AleraTokens.foregroundFaint,
                          ),
                          const SizedBox(height: AleraTokens.space12),
                          Text(
                            'Offer expired - generate a new one',
                            textAlign: .center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : AleraQrCode(data: widget.grant.toQrJson()),
            ),
            const SizedBox(height: AleraTokens.space16),
            Text(
              'Scan with the Alera mobile app',
              textAlign: .center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: .w600,
              ),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              '${widget.grant.hostName} · ${widget.grant.endpoint}',
              textAlign: .center,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              _expired ? 'Offer expired' : _countdownLabel,
              textAlign: .center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _expired ? AleraTokens.error : AleraTokens.warning,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cancelling ? null : _cancelOffer,
                    icon: const Icon(AleraIcons.cancel, size: 16),
                    label: const Text('Cancel Offer'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _expired ? null : _copyPayload,
                    icon: const Icon(AleraIcons.copy, size: 16),
                    label: Text(_copied ? 'Copied' : 'Copy Pairing JSON'),
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
