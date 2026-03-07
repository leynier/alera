import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Shows a full-screen dialog displaying the image at [path].
/// The image can be zoomed and panned via [InteractiveViewer].
/// A circular close button is placed at the top-right corner.
void showImageZoomDialog(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => _ImageZoomOverlay(path: path),
  );
}

class _ImageZoomOverlay extends StatelessWidget {
  const _ImageZoomOverlay({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Dismiss when tapping the background.
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const SizedBox.expand(),
        ),
        // Centered zoomable image.
        Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image,
                size: 48,
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
        ),
        // Close button.
        Positioned(
          bottom: AleraTokens.space12,
          left: 0,
          right: 0,
          child: Center(
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                backgroundColor: AleraTokens.surface.withValues(alpha: 0.6),
                shape: const CircleBorder(),
              ),
              icon: const Icon(
                Icons.close,
                size: 20,
                color: AleraTokens.foreground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
