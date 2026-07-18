import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:flutter/material.dart';

/// Confirmation step shown once an offer parses: host identity, endpoint,
/// a live expiry countdown, and an optional device name before pairing.
class PairingConfirmCard extends StatefulWidget {
  const PairingConfirmCard({
    super.key,
    required this.offer,
    required this.pairing,
    required this.onPair,
    required this.onScanAgain,
  });

  final PairingOffer offer;
  final bool pairing;
  final ValueChanged<String?> onPair;
  final VoidCallback onScanAgain;

  @override
  State<PairingConfirmCard> createState() => _PairingConfirmCardState();
}

class _PairingConfirmCardState extends State<PairingConfirmCard> {
  final TextEditingController _deviceName = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(AleraTokens.expiryTickInterval, (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _deviceName.dispose();
    super.dispose();
  }

  String get _expiryLabel {
    final remaining = widget.offer.expiresAt.toUtc().difference(
      DateTime.now().toUtc(),
    );
    if (remaining.isNegative) {
      return 'Offer Expired';
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    return 'Expires In $minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = widget.offer.isExpired;
    final endpoint = Uri.parse(widget.offer.endpoint);
    return ListView(
      padding: AleraTokens.pagePadding,
      children: <Widget>[
        Card(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: AleraTokens.iconLg,
                      height: AleraTokens.iconLg,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(
                          alpha: AleraTokens.emphasisOverlayAlpha,
                        ),
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                      ),
                      child: Icon(
                        Icons.computer,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.offer.hostName,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AleraTokens.spaceXs),
                          Text(
                            '${endpoint.host}:${endpoint.port}',
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AleraTokens.spaceLg),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.timer_outlined,
                      size: AleraTokens.spaceLg,
                      color: expired
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AleraTokens.spaceSm),
                    Text(
                      _expiryLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: expired
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        TextField(
          controller: _deviceName,
          enabled: !widget.pairing,
          decoration: const InputDecoration(
            labelText: 'Device Name (Optional)',
            helperText: 'How This Phone Appears On The Desktop',
          ),
        ),
        const SizedBox(height: AleraTokens.spaceLg),
        FilledButton.icon(
          onPressed: widget.pairing || expired
              ? null
              : () {
                  final name = _deviceName.text.trim();
                  widget.onPair(name.isEmpty ? null : name);
                },
          icon: widget.pairing
              ? const SizedBox.square(
                  dimension: AleraTokens.spaceLg,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                )
              : const Icon(Icons.link),
          label: Text(widget.pairing ? 'Pairing' : 'Pair'),
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        TextButton(
          onPressed: widget.pairing ? null : widget.onScanAgain,
          child: const Text('Scan Again'),
        ),
      ],
    );
  }
}
