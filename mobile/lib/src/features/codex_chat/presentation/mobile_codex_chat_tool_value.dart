part of 'mobile_codex_chat_screen.dart';

const _mobileCodexToolPageSize = 24;
const _mobileCodexToolNodeLimit = 512;
const _mobileCodexToolDepthLimit = 12;
const _mobileCodexToolTextLimit = 64 * 1024;

class const _MobileCodexToolValue({
  required final Object? value,
  final int depth = 0,
  final int nodeBudget = _mobileCodexToolNodeLimit,
  final String? paginationId,
}) extends StatefulWidget {
  @override
  State<_MobileCodexToolValue> createState() => _MobileCodexToolValueState();
}

class _MobileCodexToolValueState extends State<_MobileCodexToolValue> {
  var _visibleItemCount = _mobileCodexToolPageSize;
  late Object? _displayValue;
  var _paginationRestored = false;

  @override
  void initState() {
    super.initState();
    _displayValue = _boundMobileCodexToolValue(
      widget.value,
      depth: widget.depth,
      nodeBudget: widget.nodeBudget,
    );
  }

  @override
  void didUpdateWidget(covariant _MobileCodexToolValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    final boundsChanged =
        oldWidget.depth != widget.depth ||
        oldWidget.nodeBudget != widget.nodeBudget;
    final paginationChanged = oldWidget.paginationId != widget.paginationId;
    if (boundsChanged || paginationChanged) {
      _visibleItemCount = _mobileCodexToolPageSize;
      _paginationRestored = false;
    }
    if (!identical(oldWidget.value, widget.value) || boundsChanged) {
      _displayValue = _boundMobileCodexToolValue(
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
    if (value is _MobileCodexToolMediaValue) {
      return _MobileCodexToolMediaSummary(value: value);
    }
    if (value is _MobileCodexToolTruncation) {
      return Text(value.message, style: Theme.of(context).textTheme.bodySmall);
    }
    if (value is _MobileCodexToolTextPreview) {
      return Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          _MobileCodexToolLiteralText(text: value.text),
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
    if (value is List) return _listValue(context, value);
    if (value is Iterable && value is! String) {
      return _listValue(
        context,
        value.take(_visibleItemCount + 1).toList(growable: false),
      );
    }
    if (value is String) return _MobileCodexToolLiteralText(text: value);
    return SelectableText('$value');
  }

  Widget _mapValue(BuildContext context, Map<Object?, Object?> value) {
    final type = value['type']?.toString().toLowerCase();
    if ((type == 'text' || type == 'inputtext') && value['text'] is String) {
      return _MobileCodexToolValue(
        value: value['text'],
        depth: widget.depth + 1,
        nodeBudget: widget.nodeBudget - 1,
        paginationId: '${widget.paginationId}/text',
      );
    }
    if (type == 'resource_link' && value['uri'] != null) {
      final name = value['title'] ?? value['name'] ?? value['uri'];
      return _MobileCodexToolValue(
        value: '$name\n${value['uri']}',
        depth: widget.depth + 1,
        nodeBudget: widget.nodeBudget - 1,
        paginationId: '${widget.paginationId}/resource-link',
      );
    }
    if (type == 'resource' && value['resource'] != null) {
      return _MobileCodexToolValue(
        value: value['resource'],
        depth: widget.depth + 1,
        nodeBudget: widget.nodeBudget - 1,
        paginationId: '${widget.paginationId}/resource',
      );
    }
    final entryCount = value.length - (value.containsKey('_meta') ? 1 : 0);
    if (entryCount == 0) {
      return Text('No content', style: Theme.of(context).textTheme.bodySmall);
    }
    final childCapacity = math.max(0, widget.nodeBudget - 1);
    if (childCapacity == 0) {
      return const _MobileCodexToolValue(
        value: _MobileCodexToolTruncation('Additional content hidden.'),
        nodeBudget: 1,
      );
    }
    final visibleLimit = math.min(_visibleItemCount, childCapacity);
    final entries = value.entries
        .where((entry) => entry.key != '_meta')
        .take(visibleLimit)
        .toList(growable: false);
    final childBudget = math.max(1, childCapacity ~/ entries.length);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final entry in entries)
          _MobileCodexToolEntry(
            label: _mobileToolFieldLabel('${entry.key}'),
            value: entry.value,
            depth: widget.depth,
            nodeBudget: childBudget,
            paginationId: '${widget.paginationId}/${entry.key}',
          ),
        if (entryCount > entries.length && entries.length < childCapacity)
          _showMoreButton(entryCount - entries.length),
        if (entryCount > entries.length && entries.length >= childCapacity)
          const _MobileCodexToolValue(
            value: _MobileCodexToolTruncation('Additional content hidden.'),
            nodeBudget: 1,
          ),
      ],
    );
  }

  Widget _listValue(BuildContext context, List<Object?> value) {
    if (value.isEmpty) {
      return Text('No items', style: Theme.of(context).textTheme.bodySmall);
    }
    final childCapacity = math.max(0, widget.nodeBudget - 1);
    if (childCapacity == 0) {
      return const _MobileCodexToolValue(
        value: _MobileCodexToolTruncation('Additional content hidden.'),
        nodeBudget: 1,
      );
    }
    final visibleCount = math.min(
      math.min(_visibleItemCount, childCapacity),
      value.length,
    );
    final childBudget = math.max(1, childCapacity ~/ visibleCount);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (var index = 0; index < visibleCount; index += 1)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space6),
            child: _MobileCodexToolValue(
              value: value[index],
              depth: widget.depth + 1,
              nodeBudget: childBudget,
              paginationId: '${widget.paginationId}/$index',
            ),
          ),
        if (value.length > visibleCount && visibleCount < childCapacity)
          _showMoreButton(value.length - visibleCount),
        if (value.length > visibleCount && visibleCount >= childCapacity)
          const _MobileCodexToolValue(
            value: _MobileCodexToolTruncation('Additional content hidden.'),
            nodeBudget: 1,
          ),
      ],
    );
  }

  Widget _showMoreButton(int hiddenCount) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: () {
        setState(() => _visibleItemCount += _mobileCodexToolPageSize);
        final paginationId = widget.paginationId;
        if (paginationId != null) {
          PageStorage.maybeOf(
            context,
          )?.writeState(context, _visibleItemCount, identifier: paginationId);
        }
      },
      child: Text(
        'Show ${math.min(_mobileCodexToolPageSize, hiddenCount)} More',
      ),
    ),
  );
}

class const _MobileCodexToolLiteralText({required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      SelectableText(text, style: AleraTokens.monoStyle);
}

class const _MobileCodexToolEntry({
  required final String label,
  required final Object? value,
  required final int depth,
  required final int nodeBudget,
  required final String paginationId,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final nested =
        value is Map ||
        value is Iterable && value is! String ||
        value is _MobileCodexToolMediaValue ||
        value is _MobileCodexToolTextPreview ||
        value is _MobileCodexToolTruncation;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: nested
          ? Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
                const SizedBox(height: AleraTokens.space4),
                Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space8),
                  child: _MobileCodexToolValue(
                    value: value,
                    depth: depth + 1,
                    nodeBudget: nodeBudget,
                    paginationId: paginationId,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                SizedBox(
                  width: AleraTokens.space48 * 2,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: AleraTokens.foregroundMuted),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: _MobileCodexToolValue(
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

Object? _boundMobileCodexToolValue(
  Object? value, {
  required int depth,
  required int nodeBudget,
}) {
  if (nodeBudget <= 0) {
    return const _MobileCodexToolTruncation('Additional content hidden.');
  }
  if (value is String && value.length > _mobileCodexToolTextLimit) {
    return _MobileCodexToolTextPreview(
      value.substring(0, _mobileCodexToolTextLimit),
      value.length - _mobileCodexToolTextLimit,
    );
  }
  if (value is Map) {
    final media = _mobileCodexToolMediaValue(value);
    if (media != null) return media;
  }
  if ((value is Map || value is Iterable && value is! String) &&
      depth >= _mobileCodexToolDepthLimit) {
    return const _MobileCodexToolTruncation(
      'Nested content hidden at the display depth limit.',
    );
  }
  return value;
}

class const _MobileCodexToolTextPreview(
  final String text,
  final int hiddenCharacters,
);

class const _MobileCodexToolTruncation(final String message);
