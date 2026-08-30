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
    final decoded = const Utf8Decoder(allowMalformed: true)
        .convert(combined, 0, decodeEnd);
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

class _MobileWorkspaceFileViewerView extends StatelessWidget {
  const _MobileWorkspaceFileViewerView({
    required this.displayName,
    required this.range,
    required this.loading,
    required this.sharing,
    required this.onShare,
    required this.body,
  });

  final String displayName;
  final MobileWorkspaceFileRange? range;
  final bool loading;
  final bool sharing;
  final Future<void> Function(BuildContext context) onShare;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(displayName),
      actions: <Widget>[
        if (range != null && mobileWorkspaceFileCanShare(range!.totalBytes))
          Builder(
            builder: (shareContext) => IconButton(
              tooltip: 'Share File',
              onPressed: loading || sharing
                  ? null
                  : () => unawaited(onShare(shareContext)),
              icon: sharing
                  ? const SizedBox.square(
                      dimension: AleraTokens.iconSm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_outlined),
            ),
          ),
      ],
    ),
    body: body,
  );
}

class _MobileWorkspaceFileViewerBody extends StatelessWidget {
  const _MobileWorkspaceFileViewerBody({
    required this.range,
    required this.error,
    required this.rasterFile,
    required this.lines,
    required this.targetLine,
    required this.loadedPreviewBytes,
    required this.loading,
    required this.sharing,
    required this.scrollController,
    required this.targetLineKey,
    required this.onLoadMore,
  });

  final MobileWorkspaceFileRange? range;
  final Object? error;
  final File? rasterFile;
  final List<String> lines;
  final int? targetLine;
  final int loadedPreviewBytes;
  final bool loading;
  final bool sharing;
  final ScrollController scrollController;
  final GlobalKey targetLineKey;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return _MobileError(message: error.toString(), onRetry: onLoadMore);
    }
    final range = this.range;
    if (range == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final canLoadMore =
        range.totalBytes <= maxMobileWorkspacePreviewBytes &&
        loadedPreviewBytes < maxMobileWorkspacePreviewBytes;
    final busy = loading || sharing;
    if (mobileCodexCanRasterPreviewMime(range.mimeType)) {
      return _MobileRemoteImagePreview(
        file: rasterFile,
        complete: range.nextOffset >= range.totalBytes,
        canLoadMore: canLoadMore,
        loading: busy,
        onLoadMore: onLoadMore,
      );
    }
    if (range.isText) {
      return _MobileWorkspaceTextPreview(
        lines: lines,
        targetLine: targetLine,
        hasMore: range.nextOffset < range.totalBytes,
        previewLimitReached:
            loadedPreviewBytes >= maxMobileWorkspacePreviewBytes,
        loading: loading,
        sharing: sharing,
        scrollController: scrollController,
        targetLineKey: targetLineKey,
        onLoadMore: onLoadMore,
      );
    }
    return _MobileUnsupportedFilePreview(
      complete: range.nextOffset >= range.totalBytes,
      shareable: mobileWorkspaceFileCanShare(range.totalBytes),
      canLoadMore: canLoadMore,
      loading: busy,
      onLoadMore: onLoadMore,
    );
  }
}

class _MobileWorkspaceTextPreview extends StatelessWidget {
  const _MobileWorkspaceTextPreview({
    required this.lines,
    required this.targetLine,
    required this.hasMore,
    required this.previewLimitReached,
    required this.loading,
    required this.sharing,
    required this.scrollController,
    required this.targetLineKey,
    required this.onLoadMore,
  });

  final List<String> lines;
  final int? targetLine;
  final bool hasMore;
  final bool previewLimitReached;
  final bool loading;
  final bool sharing;
  final ScrollController scrollController;
  final GlobalKey targetLineKey;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: scrollController,
    itemCount: lines.length + (hasMore ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == lines.length) {
        return Padding(
          padding: AleraTokens.contentPadding,
          child: FilledButton(
            onPressed: loading || sharing || previewLimitReached
                ? null
                : () => unawaited(onLoadMore()),
            child: Text(
              loading
                  ? 'Loading...'
                  : previewLimitReached
                  ? 'Preview Limit Reached'
                  : 'Load More',
            ),
          ),
        );
      }
      final number = index + 1;
      final highlighted = number == targetLine;
      return Container(
        key: highlighted ? targetLineKey : null,
        color: highlighted ? AleraTokens.accentSubtle : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AleraTokens.space48,
              child: Text('$number', style: AleraTokens.monoStyle),
            ),
            Expanded(
              child: SelectableText(
                lines[index],
                style: AleraTokens.monoStyle.copyWith(
                  color: highlighted
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
