import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/updater/infra/mobile_external_browser.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_markdown_uri_policy.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_markdown_preview.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('WorkspaceFileViewerScreen');

enum WorkspaceFileViewMode { preview, source }

/// Markdown opens rendered, except from a search match: the match names a
/// line, and only the source view can point at one.
WorkspaceFileViewMode initialWorkspaceFileViewMode({
  required String relativePath,
  int? highlightLine,
}) {
  return isWorkspaceMarkdownPath(relativePath) && highlightLine == null
      ? WorkspaceFileViewMode.preview
      : WorkspaceFileViewMode.source;
}

class const WorkspaceFileViewerScreen({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String relativePath,
  this.highlightLine,
  final Future<bool> Function(Uri url) openExternalUrl =
      openMobileExternalBrowser,
}) extends ConsumerStatefulWidget {
  final int? highlightLine;

  @override
  ConsumerState<WorkspaceFileViewerScreen> createState() =>
      _WorkspaceFileViewerScreenState();
}

class _WorkspaceFileViewerScreenState
    extends ConsumerState<WorkspaceFileViewerScreen> {
  late final Future<MobileWorkspaceFileRange> _load = _read();
  final ScrollController _scroll = ScrollController();
  late WorkspaceFileViewMode _mode = initialWorkspaceFileViewMode(
    relativePath: widget.relativePath,
    highlightLine: widget.highlightLine,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<MobileWorkspaceFileRange> _read() async {
    final client = await ref.read(
      workspaceClientProvider(widget.hostId).future,
    );
    if (client case final MobileCodexWorkspaceClient files) {
      return files.readWorkspaceFile(
        workspaceId: widget.workspaceId,
        relativePath: widget.relativePath,
      );
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to preview workspace files.',
    );
  }

  Future<void> _openLink(String rawUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(rawUrl);
    var opened = false;
    if (isSupportedMarkdownViewerLinkUri(uri)) {
      try {
        opened = await widget.openExternalUrl(uri!);
        if (!opened) {
          _logger.warning('The browser refused a Markdown link.');
        }
      } on Object catch (error, stackTrace) {
        _logger.warning('Could not open a Markdown link.', error, stackTrace);
      }
    }
    if (!opened && messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Link cannot be opened')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewing = _mode == WorkspaceFileViewMode.preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          workspaceFileBaseName(widget.relativePath),
          overflow: .ellipsis,
        ),
        actions: <Widget>[
          if (isWorkspaceMarkdownPath(widget.relativePath))
            IconButton(
              tooltip: previewing ? 'Show Source' : 'Show Preview',
              icon: Icon(
                previewing ? AleraIcons.sourceView : AleraIcons.markdownPreview,
              ),
              onPressed: () => setState(() {
                _mode = previewing
                    ? WorkspaceFileViewMode.source
                    : WorkspaceFileViewMode.preview;
              }),
            ),
        ],
      ),
      body: FutureBuilder<MobileWorkspaceFileRange>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Text(snapshot.error.toString(), textAlign: .center),
              ),
            );
          }
          final range = snapshot.data;
          if (range == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _FileBody(
            range: range,
            mode: _mode,
            highlightLine: widget.highlightLine,
            scrollController: _scroll,
            preview: (markdown) => WorkspaceFileMarkdownPreview(
              hostId: widget.hostId,
              workspaceId: widget.workspaceId,
              relativePath: widget.relativePath,
              markdown: markdown,
              onLinkTap: (url) => unawaited(_openLink(url)),
            ),
          );
        },
      ),
    );
  }
}

class const _FileBody({
  required final MobileWorkspaceFileRange range,
  required final WorkspaceFileViewMode mode,
  required final ScrollController scrollController,
  required final Widget Function(String markdown) preview,
  final int? highlightLine,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (range.mimeType.startsWith('image/') && range.bytes.isNotEmpty) {
      return Center(
        child: Image.memory(Uint8List.fromList(range.bytes), fit: .contain),
      );
    }
    if (!range.isText) {
      return AleraEmptyState(
        icon: AleraIcons.files,
        message:
            'This file cannot be previewed on the phone (${range.mimeType}).',
      );
    }
    final text = utf8.decode(range.bytes, allowMalformed: true);
    final truncated = range.nextOffset < range.totalBytes;
    return Column(
      children: <Widget>[
        if (truncated)
          Material(
            color: AleraTokens.surfaceElevated,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space16,
                vertical: AleraTokens.space8,
              ),
              child: Text(
                'Showing the first ${range.bytes.length} bytes of ${range.totalBytes}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(
          child: mode == WorkspaceFileViewMode.preview
              ? preview(text)
              : _SourceLines(
                  lines: text.split('\n'),
                  highlightLine: highlightLine,
                  scrollController: scrollController,
                ),
        ),
      ],
    );
  }
}

class const _SourceLines({
  required final List<String> lines,
  required final ScrollController scrollController,
  final int? highlightLine,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: AleraTokens.contentPadding,
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final selected = highlightLine != null && highlightLine == index + 1;
        return ColoredBox(
          color: selected ? AleraTokens.accentSubtle : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
            child: Text(
              '${index + 1}  ${lines[index]}',
              style: AleraTokens.monoStyle.copyWith(
                color: selected
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}
