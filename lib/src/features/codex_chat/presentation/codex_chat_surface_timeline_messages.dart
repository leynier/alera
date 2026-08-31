part of 'codex_chat_surface.dart';

class _CodexUserMessage extends StatefulWidget {
  const _CodexUserMessage({
    required this.cell,
    required this.workspacePath,
    required this.onOpenAttachment,
  });

  final CodexTimelineCell cell;
  final String workspacePath;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  State<_CodexUserMessage> createState() => _CodexUserMessageState();
}

class _CodexUserMessageState extends State<_CodexUserMessage> {
  bool _hovered = false;
  bool _raw = false;
  late List<Map<String, Object?>> _attachments;

  @override
  void initState() {
    super.initState();
    _attachments = _codexTimelineAttachments(widget.cell);
  }

  @override
  void didUpdateWidget(covariant _CodexUserMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cell, widget.cell)) {
      _attachments = _codexTimelineAttachments(widget.cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.cell.markdownText ?? '';
    final rendered = widget.cell.renderedMarkdownText ?? raw;
    final attachments = _attachments;
    final steering =
        widget.cell.metadata[CodexTimelineMetadata.isSteering] == true;
    final goal = widget.cell.metadata[CodexTimelineMetadata.isGoal] == true;
    return Opacity(
      opacity: steering && widget.cell.isStreaming
          ? AleraTokens.codexSteeringOpacity
          : 1,
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.codexConversationMaxWidth,
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Padding(
              padding: const EdgeInsets.only(
                top: AleraTokens.space6,
                bottom: AleraTokens.space4,
                left: AleraTokens.codexUserMessageLeftInset,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AleraTokens.space6,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AleraTokens.space6,
                        runSpacing: AleraTokens.space6,
                        children: <Widget>[
                          for (final attachment in attachments)
                            _CodexTimelineAttachment(
                              attachment: attachment,
                              workspacePath: widget.workspacePath,
                              onOpen: widget.onOpenAttachment,
                            ),
                        ],
                      ),
                    ),
                  if (raw.trim().isNotEmpty)
                    Container(
                      key: ValueKey<String>(
                        'codex-user-message-bubble-${widget.cell.id}',
                      ),
                      padding: const EdgeInsets.all(AleraTokens.space12),
                      decoration: BoxDecoration(
                        color: AleraTokens.accentSubtle,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusLg,
                        ),
                        border: steering
                            ? Border.all(color: AleraTokens.codexSteeringBorder)
                            : null,
                      ),
                      child: _raw
                          ? SelectableText(raw)
                          : _CodexMarkdownText(
                              text: rendered,
                              workspacePath: widget.workspacePath,
                            ),
                    ),
                  if (steering)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space4),
                      child: Text(
                        widget.cell.isStreaming ? 'Steering...' : 'Steered',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                    ),
                  if (goal)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space4),
                      child: Row(
                        key: const ValueKey<String>('codex-sent-as-goal'),
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.track_changes_outlined,
                            size: AleraTokens.iconSm,
                            color: AleraTokens.foregroundFaint,
                          ),
                          const SizedBox(width: AleraTokens.space4),
                          Text(
                            'Sent as goal',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AleraTokens.foregroundFaint),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AleraTokens.space8),
                  _CodexMessageActions(
                    cell: widget.cell,
                    visible: _hovered || !kIsWeb,
                    raw: _raw,
                    copyText: raw,
                    alignment: MainAxisAlignment.end,
                    timestamp: widget.cell.createdAt,
                    timestampFirst: true,
                    onToggleRaw: () => setState(() => _raw = !_raw),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodexAssistantMessage extends StatefulWidget {
  const _CodexAssistantMessage({
    required this.cell,
    required this.workspacePath,
  });

  final CodexTimelineCell cell;
  final String workspacePath;

  @override
  State<_CodexAssistantMessage> createState() => _CodexAssistantMessageState();
}

class _CodexAssistantMessageState extends State<_CodexAssistantMessage> {
  bool _hovered = false;
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final raw = widget.cell.markdownText ?? '';
    if (raw.trim().isEmpty) return const SizedBox.shrink();
    final rendered = widget.cell.renderedMarkdownText ?? raw;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(
          top: AleraTokens.space6,
          bottom: AleraTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _raw
                ? SelectableText(raw)
                : _CodexMarkdownText(
                    text: rendered,
                    workspacePath: widget.workspacePath,
                  ),
            if (widget.cell.isStreaming)
              const Padding(
                padding: EdgeInsets.only(top: AleraTokens.space6),
                child: _CodexShimmerText(
                  text: 'Streaming...',
                  style: AleraTokens.labelMicroFaintStyle,
                ),
              ),
            if (!widget.cell.isStreaming) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              _CodexMessageActions(
                cell: widget.cell,
                visible: _hovered || !kIsWeb,
                raw: _raw,
                copyText: raw,
                alignment: MainAxisAlignment.start,
                timestamp: widget.cell.createdAt,
                onToggleRaw: () => setState(() => _raw = !_raw),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CodexProgressMessage extends StatelessWidget {
  const _CodexProgressMessage({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final text = cell.renderedMarkdownText ?? cell.markdownText ?? '';
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space2,
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted),
        child: _CodexMarkdownText(text: text),
      ),
    );
  }
}

class _CodexMarkdownText extends StatelessWidget {
  const _CodexMarkdownText({required this.text, this.workspacePath});

  final String text;
  final String? workspacePath;

  @override
  Widget build(BuildContext context) => GptMarkdownTheme(
    gptThemeData: GptMarkdownThemeData(
      brightness: Brightness.dark,
      linkColor: AleraTokens.info,
      linkHoverColor: AleraTokens.foreground,
      highlightColor: AleraTokens.accentSubtle,
      hrLineColor: AleraTokens.borderSubtle,
      autoAddDividerLineAfterH1: false,
    ),
    child: DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyMedium,
      child: GptMarkdown(
        _safeMarkdown(text),
        codeBuilder: (context, language, code, closed) =>
            _CodexMarkdownCodeBlock(
              language: language,
              code: code,
              closed: closed,
            ),
        onLinkTap: (url, _) => unawaited(_openCodexMarkdownLink(context, url)),
        imageBuilder: (context, source, width, height) {
          final resolved = _resolveCodexImageSource(source, workspacePath);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showCodexImagePreview(context, resolved),
              child: _buildCodexMarkdownImage(context, resolved, width, height),
            ),
          );
        },
      ),
    ),
  );
}

String _resolveCodexImageSource(String source, String? workspacePath) {
  final uri = _tryParseCodexUri(source);
  if (workspacePath == null ||
      workspacePath.isEmpty ||
      uri == null ||
      uri.scheme.isNotEmpty ||
      p.isAbsolute(source)) {
    return source;
  }
  return p.join(workspacePath, source);
}

Future<void> _openCodexMarkdownLink(BuildContext context, String url) async {
  final handler = _CodexLinkScope.maybeOf(context)?.onOpenLink;
  if (handler != null) await handler(url);
}

Widget _buildCodexMarkdownImage(
  BuildContext context,
  String source,
  double? width,
  double? height,
) {
  return ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: width ?? AleraTokens.imageMaxWidth,
      maxHeight: height ?? AleraTokens.imageMaxHeight,
    ),
    child: _codexImageFromSource(source, fit: BoxFit.contain),
  );
}

Widget _codexImageFromSource(String source, {BoxFit? fit}) {
  try {
    final uri = _tryParseCodexUri(source);
    if (uri?.scheme == 'data') {
      return Image.memory(
        UriData.fromUri(uri!).contentAsBytes(),
        fit: fit,
        errorBuilder: _codexImageError,
      );
    }
    if (uri == null || uri.scheme.isEmpty || uri.scheme == 'file') {
      return Image.file(
        File(uri?.scheme == 'file' ? uri!.toFilePath() : source),
        fit: fit,
        errorBuilder: _codexImageError,
      );
    }
    return Image.network(source, fit: fit, errorBuilder: _codexImageError);
  } on FormatException catch (error, stackTrace) {
    return Builder(
      builder: (context) => _codexImageError(context, error, stackTrace),
    );
  } on ArgumentError catch (error, stackTrace) {
    return Builder(
      builder: (context) => _codexImageError(context, error, stackTrace),
    );
  }
}

Uri? _tryParseCodexUri(String source) {
  try {
    return Uri.tryParse(source);
  } on ArgumentError {
    return null;
  }
}

Widget _codexImageError(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
) => const Icon(AleraIcons.imageError, color: AleraTokens.foregroundMuted);

List<Map<String, Object?>> _codexTimelineAttachments(CodexTimelineCell cell) {
  final raw = cell.metadata['attachments'];
  if (raw is! List) return const <Map<String, Object?>>[];
  final items = <Map<String, Object?>>[
    for (final value in raw)
      if (value is Map)
        value.map((key, value) => MapEntry(key.toString(), value)),
  ];
  items.sort((left, right) {
    final leftImage = _timelineAttachmentIsImage(left) ? 1 : 0;
    final rightImage = _timelineAttachmentIsImage(right) ? 1 : 0;
    return leftImage.compareTo(rightImage);
  });
  return items;
}

bool _timelineAttachmentIsImage(Map<String, Object?> attachment) {
  final type = attachment['type']?.toString().toLowerCase() ?? '';
  final kind = attachment['kind']?.toString().toLowerCase() ?? '';
  final path = attachment['path']?.toString() ?? '';
  return type.contains('image') || kind == 'image' || isCodexImagePath(path);
}

class _CodexTimelineAttachment extends StatelessWidget {
  const _CodexTimelineAttachment({
    required this.attachment,
    required this.workspacePath,
    required this.onOpen,
  });

  final Map<String, Object?> attachment;
  final String workspacePath;
  final Future<void> Function(String path, {required bool isImage}) onOpen;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path']?.toString() ?? '';
    final resolvedPath = path.isEmpty || p.isAbsolute(path)
        ? path
        : p.join(workspacePath, path);
    final name =
        attachment['displayName']?.toString() ??
        attachment['name']?.toString() ??
        p.basename(path);
    if (_timelineAttachmentIsImage(attachment)) {
      return InkWell(
        onTap: () => unawaited(onOpen(resolvedPath, isImage: true)),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          child: SizedBox(
            width: AleraTokens.codexAttachmentThumbnailSize,
            height: AleraTokens.codexAttachmentThumbnailSize,
            child: _buildCodexMarkdownImage(
              context,
              resolvedPath,
              AleraTokens.codexAttachmentThumbnailSize,
              AleraTokens.codexAttachmentThumbnailSize,
            ),
          ),
        ),
      );
    }
    final type = attachment['type']?.toString().toLowerCase() ?? '';
    final canOpen = resolvedPath.isNotEmpty && !path.startsWith('app://');
    return InkWell(
      onTap: canOpen
          ? () => unawaited(onOpen(resolvedPath, isImage: false))
          : null,
      mouseCursor: canOpen
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.contextMenuWidth,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (type == 'skill' || path.startsWith('app://'))
              Icon(
                type == 'skill' ? AleraIcons.agent : AleraIcons.link,
                size: AleraTokens.iconMd,
              )
            else
              AleraFileIcon(
                pathOrName: path,
                kind: attachment['isDirectory'] == true
                    ? AleraFileIconKind.folder
                    : AleraFileIconKind.file,
                size: AleraTokens.iconMd,
              ),
            const SizedBox(width: AleraTokens.space6),
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
