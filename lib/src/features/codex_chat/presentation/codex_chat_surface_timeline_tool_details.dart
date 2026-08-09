part of 'codex_chat_surface.dart';

class _CodexToolDetails extends StatefulWidget {
  const _CodexToolDetails({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexToolDetails> createState() => _CodexToolDetailsState();
}

class _CodexToolDetailsState extends State<_CodexToolDetails> {
  late _CodexToolDetailsProjection _projection;

  @override
  void initState() {
    super.initState();
    _projection = _CodexToolDetailsProjection.fromCell(widget.cell);
  }

  @override
  void didUpdateWidget(covariant _CodexToolDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cell, widget.cell)) {
      _projection = _CodexToolDetailsProjection.fromCell(widget.cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projection = _projection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (projection.fields.isNotEmpty)
          for (final (label, value) in projection.fields)
            _CodexToolField(label: label, value: value),
        if (projection.images.isNotEmpty) ...<Widget>[
          if (projection.fields.isNotEmpty)
            const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              for (final source in projection.images)
                InkWell(
                  onTap: () => _showCodexImagePreview(context, source),
                  mouseCursor: SystemMouseCursors.click,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    child: SizedBox(
                      width: AleraTokens.codexToolPreviewWidth,
                      height: AleraTokens.codexToolPreviewHeight,
                      child: _buildCodexMarkdownImage(
                        context,
                        source,
                        AleraTokens.codexToolPreviewWidth,
                        AleraTokens.codexToolPreviewHeight,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (projection.showDetails) ...<Widget>[
          if (projection.fields.isNotEmpty || projection.images.isNotEmpty)
            const SizedBox(height: AleraTokens.space8),
          if (projection.isDiff)
            _CodexDiffDetails(
              diff: projection.details,
              lines: projection.diffLines,
            )
          else
            _CodexToolPayload(label: 'Output', value: projection.details),
        ],
      ],
    );
  }
}

class _CodexToolDetailsProjection {
  const _CodexToolDetailsProjection({
    required this.fields,
    required this.images,
    required this.details,
    required this.showDetails,
    required this.isDiff,
    required this.diffLines,
  });

  factory _CodexToolDetailsProjection.fromCell(CodexTimelineCell cell) {
    final details = cell.detailsText ?? cell.markdownText ?? '';
    final metadata = cell.metadata;
    final rawFields = <(String, Object?)>[
      ('Query', metadata['query']),
      ('Action', metadata['action']),
      ('URL', metadata['url']),
      ('Duration', _codexDurationLabel(metadata['durationMs'])),
      ('Changes', metadata['changes']),
      ('Arguments', metadata['arguments']),
      ('Command Actions', metadata['commandActions']),
      ('Result', metadata['result']),
    ];
    final fields = <(String, String)>[
      for (final (label, value) in rawFields)
        if (!_emptyCodexDetail(value)) (label, _prettyCodexValue(value!)),
    ];
    final images = _codexDetailImages(<Object?>[details, ...metadata.values]);
    final prettyDetails = _prettyCodexValue(details);
    final isDiff =
        cell.kind == CodexTimelineKind.diff || _looksLikeDiff(details);
    return _CodexToolDetailsProjection(
      fields: List<(String, String)>.unmodifiable(fields),
      images: List<String>.unmodifiable(images),
      details: details,
      showDetails:
          details.trim().isNotEmpty &&
          !fields.any((field) => field.$2 == prettyDetails),
      isDiff: isDiff,
      diffLines: isDiff
          ? List<String>.unmodifiable(details.split('\n'))
          : const <String>[],
    );
  }

  final List<(String, String)> fields;
  final List<String> images;
  final String details;
  final bool showDetails;
  final bool isDiff;
  final List<String> diffLines;
}

class _CodexToolField extends StatelessWidget {
  const _CodexToolField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: _CodexToolPayload(label: label, value: value),
  );
}

class _CodexToolPayload extends StatelessWidget {
  const _CodexToolPayload({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
          AleraIconButton(
            tooltip: 'Copy $label',
            icon: AleraIcons.copy,
            onPressed: () => _copyCodexText(context, value, '$label copied'),
          ),
        ],
      ),
      SelectableText(value, style: AleraTokens.monoCompactStyle),
    ],
  );
}

class _CodexDiffDetails extends StatelessWidget {
  const _CodexDiffDetails({required this.diff, required this.lines});

  final String diff;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'File Changes',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
          AleraIconButton(
            tooltip: 'Copy Diff',
            icon: AleraIcons.copy,
            onPressed: () => _copyCodexText(context, diff, 'Diff copied'),
          ),
        ],
      ),
      ClipRRect(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final line in lines) _CodexDiffLine(text: line),
          ],
        ),
      ),
    ],
  );
}

class _CodexDiffLine extends StatelessWidget {
  const _CodexDiffLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (text) {
      String value when value.startsWith('+++') || value.startsWith('---') => (
        AleraTokens.surfaceVariant,
        AleraTokens.foregroundMuted,
      ),
      String value when value.startsWith('@@') => (
        AleraTokens.accentSubtle,
        AleraTokens.accent,
      ),
      String value when value.startsWith('+') => (
        AleraTokens.codexDiffAdditionBackground,
        AleraTokens.success,
      ),
      String value when value.startsWith('-') => (
        AleraTokens.codexDiffDeletionBackground,
        AleraTokens.error,
      ),
      _ => (Colors.transparent, AleraTokens.foreground),
    };
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Text(
          text,
          style: AleraTokens.monoCompactStyle.copyWith(color: foreground),
        ),
      ),
    );
  }
}

bool _emptyCodexDetail(Object? value) =>
    value == null || value is String && value.trim().isEmpty;

String _prettyCodexValue(Object value) {
  if (value is! String) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  final trimmed = value.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
  } catch (_) {
    return value;
  }
}

String? _codexDurationLabel(Object? value) {
  final milliseconds = value is num
      ? value.toDouble()
      : double.tryParse('$value');
  if (milliseconds == null) return null;
  if (milliseconds < 1000) return '${milliseconds.round()} ms';
  return '${(milliseconds / 1000).toStringAsFixed(1)} s';
}

bool _looksLikeDiff(String value) =>
    value.startsWith('diff --git') || value.contains('\n@@ ');

List<String> _codexDetailImages(Iterable<Object?> roots) {
  final images = <String>{};
  void collect(Object? value) {
    if (value is Map) {
      value.values.forEach(collect);
      return;
    }
    if (value is Iterable && value is! String) {
      value.forEach(collect);
      return;
    }
    if (value is! String) return;
    final candidates = RegExp(
      r'''(?:data:image/[^\s]+|https?://[^\s"']+|file://[^\s"']+|(?:[A-Za-z]:[\\/]|/)[^\n"']+)''',
    ).allMatches(value);
    for (final match in candidates) {
      final source = match.group(0)!;
      if (source.startsWith('data:image/') ||
          isCodexImagePath(
            _decodeCodexImageCandidate(source).split('?').first,
          )) {
        images.add(source);
      }
    }
  }

  roots.forEach(collect);
  return images.take(8).toList(growable: false);
}

String _decodeCodexImageCandidate(String source) {
  try {
    return Uri.decodeFull(source);
  } on FormatException {
    return source;
  } on ArgumentError {
    return source;
  }
}

Future<void> _copyCodexText(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AleraToast.show(context, message: message);
}
