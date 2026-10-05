import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Desktop pairing path, shared by the manual-first screen and the paste
/// sheet so both describe the same steps.
const String pairingDesktopSteps =
    'In Alera on your computer, go to Settings > Mobile Devices, generate a '
    'pairing QR code under Link A Device, and select Copy Pairing JSON.';

/// The CLI alternative to the desktop pairing flow, with the command in a
/// selectable block so it can be copied onto the computer.
class const PairingCliHint({super.key, final TextAlign textAlign = .start})
    extends StatelessWidget {
  static const String command = 'alera mobile --json pairing create';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(
          'Without the desktop app, run this on the computer and paste its '
          'output:',
          textAlign: textAlign,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.spaceMd,
              vertical: AleraTokens.spaceSm,
            ),
            child: SelectableText(
              command,
              textAlign: textAlign,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foreground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
