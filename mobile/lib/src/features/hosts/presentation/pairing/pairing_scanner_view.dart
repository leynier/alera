import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-bleed QR scanner with a centered viewfinder frame, torch toggle, and
/// a manual entry escape hatch. Falls back to [onScannerUnavailable] copy when
/// the camera cannot start (permission denied, no camera, simulator).
class PairingScannerView extends StatefulWidget {
  const PairingScannerView({
    super.key,
    required this.onOffer,
    required this.onEnterManually,
  });

  final ValueChanged<String> onOffer;
  final VoidCallback onEnterManually;

  @override
  State<PairingScannerView> createState() => _PairingScannerViewState();
}

class _PairingScannerViewState extends State<PairingScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    torchEnabled: false,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        _handled = true;
        widget.onOffer(rawValue);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MobileScanner(
          controller: _controller,
          onDetect: _handleBarcode,
          errorBuilder: (context, error) =>
              _ScannerUnavailable(onEnterManually: widget.onEnterManually),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: AleraTokens.pairingViewfinderSize,
              height: AleraTokens.pairingViewfinderSize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AleraTokens.foreground,
                  width: AleraTokens.strokeSm,
                ),
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: AleraTokens.spaceXl),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.spaceLg,
                  vertical: AleraTokens.spaceSm,
                ),
                decoration: BoxDecoration(
                  color: AleraTokens.background.withValues(
                    alpha: AleraTokens.scrimAlpha,
                  ),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                ),
                child: Text(
                  'Point The Camera At The Pairing QR',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.spaceXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton.filledTonal(
                    tooltip: 'Toggle Torch',
                    onPressed: _controller.toggleTorch,
                    icon: const Icon(Icons.flashlight_on_outlined),
                  ),
                  const SizedBox(height: AleraTokens.spaceMd),
                  FilledButton.tonalIcon(
                    onPressed: widget.onEnterManually,
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('Enter Code Manually'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.onEnterManually});

  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.background,
      child: Center(
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.no_photography_outlined,
                size: AleraTokens.emptyIcon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AleraTokens.spaceLg),
              Text(
                'Camera Unavailable',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AleraTokens.spaceSm),
              Text(
                'Allow Camera Access Or Paste The Pairing Offer Instead.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AleraTokens.spaceLg),
              FilledButton.icon(
                onPressed: onEnterManually,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Enter Code Manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
