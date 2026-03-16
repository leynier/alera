import 'dart:io';
import 'dart:typed_data';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows a full-screen zoom dialog for a local file image at [path].
void showImageZoomDialog(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _ImageZoomOverlay(
      imageProvider: FileImage(File(path)),
    ),
  );
}

/// Shows a full-screen zoom dialog for an image identified by [uri].
/// Uses [NetworkImage] for http/https URIs, [FileImage] for file URIs.
/// When the URI is http/https an "open in browser" button is shown.
void showImageZoomDialogForUri(BuildContext context, Uri uri) {
  final ImageProvider provider;
  Uri? externalUrl;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    provider = NetworkImage(uri.toString());
    externalUrl = uri;
  } else if (uri.scheme == '' || uri.scheme == 'file') {
    provider = FileImage(File(uri.toFilePath()));
  } else {
    provider = MemoryImage(Uint8List(0));
  }
  showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (context) => _ImageZoomOverlay(
      imageProvider: provider,
      externalUrl: externalUrl,
    ),
  );
}

class _ImageZoomOverlay extends StatelessWidget {
  const _ImageZoomOverlay({
    required this.imageProvider,
    this.externalUrl,
  });

  final ImageProvider imageProvider;
  final Uri? externalUrl;

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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              child: Image(
                image: imageProvider,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  size: 48,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          ),
        ),
        // Bottom action row.
        Positioned(
          bottom: AleraTokens.space12,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (externalUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: AleraTokens.space8,
                    ),
                    child: IconButton(
                      onPressed: () => launchUrl(
                        externalUrl!,
                        mode: LaunchMode.externalApplication,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            AleraTokens.surface.withValues(alpha: 0.6),
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(
                        Icons.open_in_new,
                        size: 20,
                        color: AleraTokens.foreground,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        AleraTokens.surface.withValues(alpha: 0.6),
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: AleraTokens.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
