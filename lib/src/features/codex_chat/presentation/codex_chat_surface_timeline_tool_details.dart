part of 'codex_chat_surface.dart';

class _CodexToolDetails extends StatelessWidget {
  const _CodexToolDetails({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final details = cell.detailsText ?? cell.markdownText ?? '';
    final metadata = cell.metadata;
    final fields = <(String, Object?)>[
      ('Query', metadata['query']),
      ('Action', metadata['action']),
      ('URL', metadata['url']),
      ('Duration', _codexDurationLabel(metadata['durationMs'])),
      ('Changes', metadata['changes']),
      ('Arguments', metadata['arguments']),
      ('Command Actions', metadata['commandActions']),
      ('Result', metadata['result']),
    ].where((entry) => !_emptyCodexDetail(entry.$2)).toList(growable: false);
    final images = _codexDetailImages(<Object?>[details, ...metadata.values]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (fields.isNotEmpty)
          for (final (label, value) in fields)
            _CodexToolField(label: label, value: value!),
        if (images.isNotEmpty) ...<Widget>[
          if (fields.isNotEmpty) const SizedBox(height: AleraTokens.space8),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              for (final source in images)
                InkWell(
                  onTap: () => _showCodexImagePreview(context, source),
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
        if (details.trim().isNotEmpty &&
            !fields.any(
              (field) => _sameCodexDetail(field.$2, details),
            )) ...<Widget>[
          if (fields.isNotEmpty || images.isNotEmpty)
            const SizedBox(height: AleraTokens.space8),
          if (cell.kind == CodexTimelineKind.diff || _looksLikeDiff(details))
            _CodexDiffDetails(diff: details)
          else
            _CodexToolPayload(label: 'Output', value: details),
        ],
      ],
    );
  }
}

class _CodexToolField extends StatelessWidget {
  const _CodexToolField({required this.label, required this.value});

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: _CodexToolPayload(label: label, value: _prettyCodexValue(value)),
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
  const _CodexDiffDetails({required this.diff});

  final String diff;

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
            for (final line in diff.split('\n')) _CodexDiffLine(text: line),
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

bool _sameCodexDetail(Object? value, String details) =>
    _prettyCodexValue(value ?? '') == _prettyCodexValue(details);

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
          isCodexImagePath(Uri.decodeFull(source).split('?').first)) {
        images.add(source);
      }
    }
  }

  roots.forEach(collect);
  return images.take(8).toList(growable: false);
}

Future<void> _copyCodexText(
  BuildContext context,
  String text,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AleraToast.show(context, message: message);
}
