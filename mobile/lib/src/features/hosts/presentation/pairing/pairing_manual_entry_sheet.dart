import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Bottom sheet for pasting a pairing offer JSON by hand. Returns the entered
/// text through [Navigator.pop]; validation happens in the pairing controller
/// so scanner and manual input share one code path.
Future<String?> showPairingManualEntrySheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _PairingManualEntrySheet(),
  );
}

class _PairingManualEntrySheet extends StatefulWidget {
  const _PairingManualEntrySheet();

  @override
  State<_PairingManualEntrySheet> createState() =>
      _PairingManualEntrySheetState();
}

class _PairingManualEntrySheetState extends State<_PairingManualEntrySheet> {
  final TextEditingController _controller = TextEditingController();
  bool _hasInput = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasInput = _controller.text.trim().isNotEmpty;
      if (hasInput != _hasInput) {
        setState(() {
          _hasInput = hasInput;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AleraTokens.spaceLg,
        right: AleraTokens.spaceLg,
        top: AleraTokens.spaceLg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AleraTokens.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Paste Pairing Offer',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          Text(
            'Copy The Offer JSON From The Desktop Pairing Dialog.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: AleraTokens.pairingInputMinLines,
            maxLines: AleraTokens.pairingInputMaxLines,
            decoration: const InputDecoration(
              labelText: 'Pairing Offer JSON',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          FilledButton.icon(
            onPressed: _hasInput
                ? () => Navigator.of(context).pop(_controller.text)
                : null,
            icon: const Icon(Icons.link),
            label: const Text('Use This Offer'),
          ),
        ],
      ),
    );
  }
}
