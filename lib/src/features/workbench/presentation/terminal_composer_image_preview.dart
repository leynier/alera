import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

void showTerminalComposerImagePreview(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    barrierColor: AleraTokens.barrierDark,
    builder: (context) => _TerminalComposerImagePreview(path: path),
  );
}

class const _TerminalComposerImagePreview({required final String path})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey<String>('terminal-composer-image-preview'),
      children: <Widget>[
        GestureDetector(
          key: const ValueKey<String>(
            'terminal-composer-image-preview-background',
          ),
          onTap: () => Navigator.of(context).pop(),
          child: const SizedBox.expand(),
        ),
        Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              child: Image.file(
                File(path),
                fit: .contain,
                errorBuilder: (_, _, _) => const Icon(
                  AleraIcons.imageError,
                  size: AleraTokens.space48,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: AleraTokens.space12,
          left: 0,
          right: 0,
          child: Center(
            child: AleraIconButton(
              key: const ValueKey<String>(
                'terminal-composer-image-preview-close',
              ),
              tooltip: 'Close Image Preview',
              icon: AleraIcons.close,
              iconColor: AleraTokens.foreground,
              backgroundColor: AleraTokens.surface,
              minSize: AleraTokens.space32,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ],
    );
  }
}
