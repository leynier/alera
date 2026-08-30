part of 'codex_chat_surface.dart';

class _CodexStructuredToolPayload extends StatelessWidget {
  const _CodexStructuredToolPayload({
    required this.label,
    required this.value,
    required this.paginationId,
  });

  final String label;
  final Object value;
  final String paginationId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AleraTokens.foregroundFaint),
              ),
            ),
            AleraIconButton(
              tooltip: 'Copy $label',
              icon: AleraIcons.copy,
              onPressed: () => unawaited(
                _copyCodexToolValue(context, value, '$label copied'),
              ),
            ),
          ],
        ),
        _CodexStructuredToolValue(value: value, paginationId: paginationId),
      ],
    ),
  );
}

const _codexStructuredToolPageSize = 24;
const _codexStructuredToolNodeLimit = 512;
const _codexStructuredToolDepthLimit = 12;
const _codexStructuredToolTextLimit = 64 * 1024;

class _CodexStructuredToolValue extends StatefulWidget {
  const _CodexStructuredToolValue({
    required this.value,
    this.depth = 0,
    this.nodeBudget = _codexStructuredToolNodeLimit,
    this.paginationId,
  });

  final Object? value;
  final int depth;
  final int nodeBudget;
  final String? paginationId;

  @override
  State<_CodexStructuredToolValue> createState() =>
      _CodexStructuredToolValueState();
}

class _CodexStructuredToolValueState extends State<_CodexStructuredToolValue> {
  var _visibleItemCount = _codexStructuredToolPageSize;
  late Object? _displayValue;
  var _paginationRestored = false;

  @override
  void initState() {
    super.initState();
    _displayValue = _boundCodexToolValue(
      widget.value,
      depth: widget.depth,
      nodeBudget: widget.nodeBudget,
    );
  }

  @override
  void didUpdateWidget(covariant _CodexStructuredToolValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    final boundsChanged =
        oldWidget.depth != widget.depth ||
        oldWidget.nodeBudget != widget.nodeBudget;
    final paginationChanged = oldWidget.paginationId != widget.paginationId;
    if (boundsChanged || paginationChanged) {
      _visibleItemCount = _codexStructuredToolPageSize;
      _paginationRestored = false;
    }
    if (!identical(oldWidget.value, widget.value) || boundsChanged) {
      _displayValue = _boundCodexToolValue(
        widget.value,
        depth: widget.depth,
        nodeBudget: widget.nodeBudget,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_paginationRestored) return;
    _paginationRestored = true;
    final paginationId = widget.paginationId;
    if (paginationId == null) return;
    final stored = PageStorage.maybeOf(context)
        ?.readState(context, identifier: paginationId);
    if (stored is int && stored > _visibleItemCount) {
      _visibleItemCount = stored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _displayValue;
    if (value is _CodexToolMediaValue) {
      return _CodexToolMediaSummary(value: value);
    }
    if (value is _CodexToolTruncation) {
      return Text(value.message, style: Theme.of(context).textTheme.bodySmall);
    }
    if (value is _CodexToolTextPreview) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CodexToolLiteralText(text: value.text),
          const SizedBox(height: AleraTokens.space4),
          Text(
            '${value.hiddenCharacters} additional characters hidden. Copy the section to access the complete value.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        ],
      );
    }
    if (value is Map) return _mapValue(context, value);
    if (value is List) {
      return _listValue(context, value);
    }
    if (value is Iterable && value is! String) {
      return _listValue(context, value.take(_visibleItemCount + 1).toList());
    }
    if (value is String) return _CodexToolLiteralText(text: value);
    return SelectableText('$value', style: AleraTokens.monoCompactStyle);
  }

  Widget _mapValue(BuildContext context, Map<Object?, Object?> map) {
    final type = map['type']?.toString().toLowerCase();
    if ((type == 'text' || type == 'inputtext') && map['text'] is String) {
      return _CodexStructuredToolValue(
        value: map['text'],
        depth: widget.depth + 1,
        nodeBudget: widget.nodeBudget - 1,
        paginationId: '${widget.paginationId}/text',
      );
    }
    if (type == 'resource_link') {
      final name = map['title'] ?? map['name'] ?? map['uri'];
      final uri = map['uri'];
      if (uri != null) {
        return _CodexStructuredToolValue(
          value: '$name\n$uri',
          depth: widget.depth + 1,
          nodeBudget: widget.nodeBudget - 1,
          paginationId: '${widget.paginationId}/resource-link',
        );
      }
    }
    if (type == 'resource' && map['resource'] != null) {
      return _CodexStructuredToolValue(
        value: map['resource'],
        depth: widget.depth + 1,
        nodeBudget: widget.nodeBudget - 1,
        paginationId: '${widget.paginationId}/resource',
      );
    }
    final entryCount = map.length - (map.containsKey('_meta') ? 1 : 0);
    if (entryCount == 0) {
      return Text('No content', style: Theme.of(context).textTheme.bodySmall);
    }
    final childCapacity = math.max(0, widget.nodeBudget - 1);
    if (childCapacity == 0) {
      return const _CodexStructuredToolValue(
        value: _CodexToolTruncation('Additional content hidden.'),
        nodeBudget: 1,
      );
    }
    final visibleLimit = math.min(_visibleItemCount, childCapacity);
    final entries = map.entries
        .where((entry) => entry.key != '_meta')
        .take(visibleLimit)
        .toList(growable: false);
    final childBudget = math.max(1, childCapacity ~/ entries.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final entry in entries)
          _CodexStructuredToolEntry(
            label: _codexToolFieldLabel('${entry.key}'),
            value: entry.value,
            depth: widget.depth,
            nodeBudget: childBudget,
            paginationId: '${widget.paginationId}/${entry.key}',
          ),
        if (entryCount > entries.length && entries.length < childCapacity)
          _showMoreButton(entryCount - entries.length),
        if (entryCount > entries.length && entries.length >= childCapacity)
          const _CodexStructuredToolValue(
            value: _CodexToolTruncation('Additional content hidden.'),
            nodeBudget: 1,
          ),
      ],
    );
  }

  Widget _listValue(BuildContext context, List<Object?> values) {
    if (values.isEmpty) {
      return Text('No items', style: Theme.of(context).textTheme.bodySmall);
    }
    final childCapacity = math.max(0, widget.nodeBudget - 1);
    if (childCapacity == 0) {
      return const _CodexStructuredToolValue(
        value: _CodexToolTruncation('Additional content hidden.'),
        nodeBudget: 1,
      );
    }
    final visibleCount = math.min(
      math.min(_visibleItemCount, childCapacity),
      values.length,
    );
    final childBudget = math.max(1, childCapacity ~/ visibleCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < visibleCount; index += 1)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : AleraTokens.space6),
            child: _CodexStructuredToolValue(
              value: values[index],
              depth: widget.depth + 1,
              nodeBudget: childBudget,
              paginationId: '${widget.paginationId}/$index',
            ),
          ),
        if (values.length > visibleCount && visibleCount < childCapacity)
          _showMoreButton(values.length - visibleCount),
        if (values.length > visibleCount && visibleCount >= childCapacity)
          const _CodexStructuredToolValue(
            value: _CodexToolTruncation('Additional content hidden.'),
            nodeBudget: 1,
          ),
      ],
    );
  }

  Widget _showMoreButton(int hiddenCount) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () {
        setState(() => _visibleItemCount += _codexStructuredToolPageSize);
        final paginationId = widget.paginationId;
        if (paginationId != null) {
          PageStorage.maybeOf(
            context,
          )?.writeState(context, _visibleItemCount, identifier: paginationId);
        }
      },
      child: Text(
        'Show ${math.min(_codexStructuredToolPageSize, hiddenCount)} More',
      ),
    ),
  );
}

Future<void> _copyCodexToolValue(
  BuildContext context,
  Object value,
  String message,
) async {
  final text = await compute(_prettyCodexValue, value);
  if (!context.mounted) return;
  await _copyCodexText(context, text, message);
}

class _CodexToolLiteralText extends StatelessWidget {
  const _CodexToolLiteralText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      SelectableText(text, style: AleraTokens.monoCompactStyle);
}

Object? _boundCodexToolValue(
  Object? value, {
  required int depth,
  required int nodeBudget,
}) {
  if (nodeBudget <= 0) {
    return const _CodexToolTruncation('Additional content hidden.');
  }
  if (value is String && value.length > _codexStructuredToolTextLimit) {
    return _CodexToolTextPreview(
      value.substring(0, _codexStructuredToolTextLimit),
      value.length - _codexStructuredToolTextLimit,
    );
  }
  if (value is Map) {
    final media = _codexToolMediaValue(value);
    if (media != null) return media;
  }
  if ((value is Map || value is Iterable && value is! String) &&
      depth >= _codexStructuredToolDepthLimit) {
    return const _CodexToolTruncation(
      'Nested content hidden at the display depth limit.',
    );
  }
  return value;
}

class _CodexToolTextPreview {
  const _CodexToolTextPreview(this.text, this.hiddenCharacters);

  final String text;
  final int hiddenCharacters;
}

class _CodexToolTruncation {
  const _CodexToolTruncation(this.message);

  final String message;
}

class _CodexStructuredToolEntry extends StatelessWidget {
  const _CodexStructuredToolEntry({
    required this.label,
    required this.value,
    required this.depth,
    required this.nodeBudget,
    required this.paginationId,
  });

  final String label;
  final Object? value;
  final int depth;
  final int nodeBudget;
  final String paginationId;

  @override
  Widget build(BuildContext context) {
    final nested = value is Map || value is Iterable && value is! String;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: nested
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
                const SizedBox(height: AleraTokens.space4),
                Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space8),
                  child: _CodexStructuredToolValue(
                    value: value,
                    depth: depth + 1,
                    nodeBudget: nodeBudget,
                    paginationId: paginationId,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AleraTokens.space48 * 2,
                  ),
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: _CodexStructuredToolValue(
                    value: value,
                    depth: depth + 1,
                    nodeBudget: nodeBudget,
                    paginationId: paginationId,
                  ),
                ),
              ],
            ),
    );
  }
}

String _codexToolFieldLabel(String key) {
  final spaced = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('_', ' ')
      .trim();
  if (spaced.isEmpty) return 'Value';
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
