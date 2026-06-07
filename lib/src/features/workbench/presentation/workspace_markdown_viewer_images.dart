import 'dart:io' show Directory, File, FileSystemException;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/presentation/workspace_markdown_uri_policy.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

Widget buildMarkdownViewerImage({
  required String workspacePath,
  required String? markdownPath,
  required String imageUrl,
  double? width,
  double? height,
}) {
  final uri = Uri.tryParse(imageUrl);
  if (isSupportedMarkdownViewerRemoteImageUri(uri)) {
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          _MarkdownViewerImagePlaceholder(width: width, height: height),
    );
  }

  final relativeImagePath = markdownPath == null
      ? null
      : resolveWorkspaceMarkdownImagePath(
          markdownPath: markdownPath,
          rawImageUrl: imageUrl,
        );
  if (relativeImagePath == null) {
    return _MarkdownViewerImagePlaceholder(width: width, height: height);
  }

  return _MarkdownViewerLocalImage(
    workspacePath: workspacePath,
    markdownPath: markdownPath!,
    imageUrl: imageUrl,
    width: width,
    height: height,
  );
}

String? resolveWorkspaceMarkdownImagePath({
  required String markdownPath,
  required String rawImageUrl,
}) {
  final trimmed = rawImageUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.startsWith('/') ||
      trimmed.startsWith(r'\') ||
      trimmed.startsWith('//') ||
      _startsWithWindowsDrive(trimmed)) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    return null;
  }

  final decodedPath = _decodeMarkdownImagePath(uri.path)?.replaceAll(r'\', '/');
  if (decodedPath == null ||
      decodedPath.isEmpty ||
      decodedPath.startsWith('/') ||
      _startsWithWindowsDrive(decodedPath)) {
    return null;
  }

  final markdownDirectory = p.posix.dirname(markdownPath);
  final joined = markdownDirectory == '.'
      ? decodedPath
      : p.posix.join(markdownDirectory, decodedPath);
  final normalized = p.posix.normalize(joined);
  if (normalized == '.' ||
      normalized == '..' ||
      normalized.startsWith('../') ||
      p.posix.isAbsolute(normalized)) {
    return null;
  }
  return normalized;
}

Future<String?> resolveWorkspaceMarkdownImageFilePath({
  required String workspacePath,
  required String markdownPath,
  required String rawImageUrl,
}) async {
  final relativeImagePath = resolveWorkspaceMarkdownImagePath(
    markdownPath: markdownPath,
    rawImageUrl: rawImageUrl,
  );
  if (relativeImagePath == null) {
    return null;
  }

  final absoluteImagePath = p.joinAll(<String>[
    workspacePath,
    ...p.posix.split(relativeImagePath),
  ]);
  try {
    final canonicalWorkspacePath = p.normalize(
      await Directory(workspacePath).resolveSymbolicLinks(),
    );
    final canonicalImagePath = p.normalize(
      await File(absoluteImagePath).resolveSymbolicLinks(),
    );
    if (p.equals(canonicalWorkspacePath, canonicalImagePath) ||
        p.isWithin(canonicalWorkspacePath, canonicalImagePath)) {
      return canonicalImagePath;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

String? _decodeMarkdownImagePath(String path) {
  try {
    return Uri.decodeFull(path);
  } on FormatException {
    return null;
  }
}

bool _startsWithWindowsDrive(String path) {
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);
}

class _MarkdownViewerLocalImage extends StatefulWidget {
  const _MarkdownViewerLocalImage({
    required this.workspacePath,
    required this.markdownPath,
    required this.imageUrl,
    this.width,
    this.height,
  });

  final String workspacePath;
  final String markdownPath;
  final String imageUrl;
  final double? width;
  final double? height;

  @override
  State<_MarkdownViewerLocalImage> createState() =>
      _MarkdownViewerLocalImageState();
}

class _MarkdownViewerLocalImageState extends State<_MarkdownViewerLocalImage> {
  late Future<String?> _imagePath;

  @override
  void initState() {
    super.initState();
    _imagePath = _resolveImagePath();
  }

  @override
  void didUpdateWidget(covariant _MarkdownViewerLocalImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.markdownPath != widget.markdownPath ||
        oldWidget.imageUrl != widget.imageUrl) {
      _imagePath = _resolveImagePath();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _imagePath,
      builder: (context, snapshot) {
        final imagePath = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            imagePath == null) {
          return _MarkdownViewerImagePlaceholder(
            width: widget.width,
            height: widget.height,
          );
        }
        return Image.file(
          File(imagePath),
          width: widget.width,
          height: widget.height,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _MarkdownViewerImagePlaceholder(
            width: widget.width,
            height: widget.height,
          ),
        );
      },
    );
  }

  Future<String?> _resolveImagePath() {
    return resolveWorkspaceMarkdownImageFilePath(
      workspacePath: widget.workspacePath,
      markdownPath: widget.markdownPath,
      rawImageUrl: widget.imageUrl,
    );
  }
}

class _MarkdownViewerImagePlaceholder extends StatelessWidget {
  const _MarkdownViewerImagePlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? AleraTokens.imageMaxWidth,
      height: height ?? AleraTokens.imageMaxHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: AleraTokens.foregroundMuted,
        size: 20,
      ),
    );
  }
}
