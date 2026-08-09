part of 'mobile_codex_chat_screen.dart';

@visibleForTesting
bool mobileCodexCanRasterPreviewMime(String mimeType) => switch (mimeType) {
  'image/png' || 'image/jpeg' || 'image/gif' || 'image/webp' => true,
  _ => false,
};

@visibleForTesting
Image mobileCodexRasterPreview(File file) => Image(
  image: ResizeImage(
    FileImage(file),
    width: AleraTokens.codexRasterPreviewCacheDimension,
    height: AleraTokens.codexRasterPreviewCacheDimension,
    policy: ResizeImagePolicy.fit,
  ),
);

@visibleForTesting
Map<String, Object?> decodeMobileCodexTextChunks(Map<String, Object?> input) {
  var carry = (input['carry']! as List).cast<int>();
  var remainder = input['remainder']! as String;
  final completed = <String>[];
  for (final rawChunk in input['chunks']! as List) {
    final chunk = rawChunk.cast<int>();
    final combined = <int>[...carry, ...chunk];
    final trailing = _incompleteUtf8TrailingBytes(combined);
    final decodeEnd = combined.length - trailing;
    final decoded = const Utf8Decoder(
      allowMalformed: true,
    ).convert(combined, 0, decodeEnd);
    final parts = '$remainder$decoded'.split('\n');
    remainder = parts.removeLast();
    completed.addAll(parts);
    carry = trailing == 0 ? const <int>[] : combined.sublist(decodeEnd);
  }
  if (input['flush'] == true && carry.isNotEmpty) {
    remainder += const Utf8Decoder(allowMalformed: true).convert(carry);
    carry = const <int>[];
  }
  return <String, Object?>{
    'lines': completed,
    'remainder': remainder,
    'carry': carry,
  };
}

int _incompleteUtf8TrailingBytes(List<int> bytes) {
  if (bytes.isEmpty) return 0;
  var leadIndex = bytes.length - 1;
  while (leadIndex >= 0 &&
      bytes.length - leadIndex <= 4 &&
      bytes[leadIndex] & 0xc0 == 0x80) {
    leadIndex -= 1;
  }
  if (leadIndex < 0) return 0;
  final lead = bytes[leadIndex];
  final expected = switch (lead) {
    < 0x80 => 1,
    >= 0xc2 && <= 0xdf => 2,
    >= 0xe0 && <= 0xef => 3,
    >= 0xf0 && <= 0xf4 => 4,
    _ => 1,
  };
  final available = bytes.length - leadIndex;
  return expected > available ? available : 0;
}

class _MobileRemoteImagePreview extends StatelessWidget {
  const _MobileRemoteImagePreview({
    required this.file,
    required this.complete,
    required this.canLoadMore,
    required this.loading,
    required this.onLoadMore,
  });

  final File? file;
  final bool complete;
  final bool canLoadMore;
  final bool loading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (complete && file != null) {
      return InteractiveViewer(
        child: Center(child: mobileCodexRasterPreview(file!)),
      );
    }
    return _MobileRemoteLoadMore(
      message: 'This image is larger than the mobile preview limit.',
      canLoadMore: canLoadMore,
      loading: loading,
      onLoadMore: onLoadMore,
    );
  }
}

class _MobileUnsupportedFilePreview extends StatelessWidget {
  const _MobileUnsupportedFilePreview({
    required this.complete,
    required this.shareable,
    required this.canLoadMore,
    required this.loading,
    required this.onLoadMore,
  });

  final bool complete;
  final bool shareable;
  final bool canLoadMore;
  final bool loading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => !shareable
      ? const Center(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Text(
              'This file is larger than the mobile sharing limit.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : complete
      ? const Center(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Text(
              'This file cannot be previewed. Use Share File to open it in another app.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : _MobileRemoteLoadMore(
          message: 'Load the remaining file before sharing it.',
          canLoadMore: canLoadMore,
          loading: loading,
          onLoadMore: onLoadMore,
        );
}

class _MobileRemoteLoadMore extends StatelessWidget {
  const _MobileRemoteLoadMore({
    required this.message,
    required this.canLoadMore,
    required this.loading,
    required this.onLoadMore,
  });

  final String message;
  final bool canLoadMore;
  final bool loading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AleraTokens.space12),
          if (canLoadMore)
            FilledButton(
              onPressed: loading ? null : () => unawaited(onLoadMore()),
              child: Text(loading ? 'Loading...' : 'Load More'),
            ),
        ],
      ),
    ),
  );
}
