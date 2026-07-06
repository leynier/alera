import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models.dart';
import '../network/mobile_runtime_client.dart';
import '../storage/host_repository.dart';
import '../theme/alera_tokens.dart';

class PairHostScreen extends StatefulWidget {
  const PairHostScreen({super.key, required this.hostRepository});

  final HostRepository hostRepository;

  @override
  State<PairHostScreen> createState() => _PairHostScreenState();
}

class _PairHostScreenState extends State<PairHostScreen> {
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
      await widget.hostRepository.savePairedHost(host, credentials.deviceToken);
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
