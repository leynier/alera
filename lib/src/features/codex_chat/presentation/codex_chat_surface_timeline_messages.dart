part of 'codex_chat_surface.dart';

class _CodexUserMessage extends StatefulWidget {
  const _CodexUserMessage({required this.cell, required this.workspacePath});

  final CodexTimelineCell cell;
  final String workspacePath;

  @override
  State<_CodexUserMessage> createState() => _CodexUserMessageState();
}

class _CodexUserMessageState extends State<_CodexUserMessage> {
  bool _hovered = false;
  bool _raw = false;

  @override
  Widget build(BuildContext context) {
    final raw = widget.cell.markdownText ?? '';
    final rendered = widget.cell.renderedMarkdownText ?? raw;
    final attachments = _codexTimelineAttachments(widget.cell);
    final steering =
        widget.cell.metadata[CodexTimelineMetadata.isSteering] == true;
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
                            ),
                        ],
                      ),
                    ),
                  if (raw.trim().isNotEmpty)
                    Container(
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
                  _CodexMessageActions(
                    visible: _hovered || !kIsWeb,
                    raw: _raw,
                    copyText: raw,
                    alignment: MainAxisAlignment.end,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: AleraTokens.iconSm,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeThin,
                      ),
                    ),
                    SizedBox(width: AleraTokens.space6),
                    Text(
                      'Streaming...',
                      style: AleraTokens.labelMicroFaintStyle,
                    ),
                  ],
                ),
              ),
            _CodexMessageActions(
              visible: _hovered || !kIsWeb,
              raw: _raw,
              copyText: raw,
              alignment: MainAxisAlignment.start,
              onToggleRaw: () => setState(() => _raw = !_raw),
            ),
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

class _CodexMessageActions extends StatelessWidget {
  const _CodexMessageActions({
    required this.visible,
    required this.raw,
    required this.copyText,
    required this.alignment,
    required this.onToggleRaw,
  });

  final bool visible;
  final bool raw;
  final String copyText;
  final MainAxisAlignment alignment;
  final VoidCallback onToggleRaw;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: AleraTokens.durationFast,
    child: IgnorePointer(
      ignoring: !visible,
      child: Row(
        mainAxisAlignment: alignment,
        children: <Widget>[
          AleraIconButton(
            tooltip: 'Copy Message',
            icon: AleraIcons.copy,
            onPressed: copyText.isEmpty
                ? null
                : () => _copyCodexText(context, copyText, 'Message copied'),
          ),
          AleraIconButton(
            tooltip: raw ? 'Show Markdown' : 'Show Raw Markdown',
            icon: raw ? AleraIcons.text : AleraIcons.code,
            onPressed: onToggleRaw,
          ),
        ],
      ),
    ),
  );
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
        onLinkTap: (url, _) {
          final scoped = _CodexLinkScope.maybeOf(context);
          unawaited(
            scoped == null
                ? _openCodexMarkdownLink(url)
                : scoped.onOpenLink(url),
          );
        },
        imageBuilder: (context, source, width, height) {
          final resolved = _resolveCodexImageSource(source, workspacePath);
          return GestureDetector(
            onTap: () => _showCodexImagePreview(context, resolved),
            child: _buildCodexMarkdownImage(context, resolved, width, height),
          );
        },
      ),
    ),
  );
}

String _resolveCodexImageSource(String source, String? workspacePath) {
  final uri = Uri.tryParse(source);
  if (workspacePath == null ||
      workspacePath.isEmpty ||
      uri == null ||
      uri.scheme.isNotEmpty ||
      p.isAbsolute(source)) {
    return source;
  }
  return p.join(workspacePath, source);
}

Future<void> _openCodexMarkdownLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final uri = Uri.tryParse(source);
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
  });

  final Map<String, Object?> attachment;
  final String workspacePath;

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
        onTap: () => _showCodexImagePreview(context, resolvedPath),
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
          ? () => unawaited(launchUrl(Uri.file(resolvedPath)))
          : null,
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
            Icon(
              type == 'skill'
                  ? AleraIcons.agent
                  : path.startsWith('app://')
                  ? AleraIcons.link
                  : AleraIcons.fileGeneric,
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
