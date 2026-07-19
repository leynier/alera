import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PairHostScreen extends ConsumerStatefulWidget {
  const PairHostScreen({super.key});

  @override
  ConsumerState<PairHostScreen> createState() => _PairHostScreenState();
}

class _PairHostScreenState extends ConsumerState<PairHostScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  bool _scannerOpen = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pairFromInput() async {
    await _pair(_controller.text);
  }

  Future<void> _pair(String rawOffer) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final offer = PairingOffer.parse(rawOffer);
      final credentials = await MobileRuntimeClient.pairDevice(offer);
      final host = PairedHostProfile.fromPairingResult(offer, credentials);
      await ref
          .read(pairedHostsControllerProvider.notifier)
          .savePairedHost(host, credentials.deviceToken);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_saving) {
      return;
    }
    String? value;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        value = rawValue;
        break;
      }
    }
    if (value == null) {
      return;
    }
    _controller.text = value;
    setState(() {
      _scannerOpen = false;
    });
    _pair(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Host')),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            TextField(
              controller: _controller,
              minLines: AleraTokens.pairingInputMinLines,
              maxLines: AleraTokens.pairingInputMaxLines,
              decoration: const InputDecoration(
                labelText: 'Pairing Offer JSON',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _pairFromInput,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: AleraTokens.spaceLg,
                            child: CircularProgressIndicator(
                              strokeWidth: AleraTokens.strokeSm,
                            ),
                          )
                        : const Icon(Icons.link),
                    label: const Text('Pair'),
                  ),
                ),
                const SizedBox(width: AleraTokens.spaceMd),
                IconButton.filledTonal(
                  tooltip: 'Scan QR',
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _scannerOpen = !_scannerOpen;
                          });
                        },
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceMd),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_scannerOpen) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceLg),
              ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                child: AspectRatio(
                  aspectRatio: AleraTokens.squareAspectRatio,
                  child: MobileScanner(onDetect: _handleBarcode),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
