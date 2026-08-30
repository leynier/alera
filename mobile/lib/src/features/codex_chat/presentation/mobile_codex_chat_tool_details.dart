part of 'mobile_codex_chat_screen.dart';

class _MobileCodexToolDetails extends StatefulWidget {
  const _MobileCodexToolDetails({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  State<_MobileCodexToolDetails> createState() =>
      _MobileCodexToolDetailsState();
}

class _MobileCodexToolDetailsState extends State<_MobileCodexToolDetails> {
  late _MobileCodexToolProjection _projection;

  @override
  void initState() {
    super.initState();
    _projection = _MobileCodexToolProjection.fromCell(widget.cell);
  }

  @override
  void didUpdateWidget(covariant _MobileCodexToolDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.cell, widget.cell)) {
      _projection = _MobileCodexToolProjection.fromCell(widget.cell);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (label, value) in _projection.overview)
        _MobileCodexToolScalar(label: label, value: value),
      if (_projection.arguments != null)
        _MobileCodexToolSection(
          label: 'Arguments',
          value: _projection.arguments!,
          paginationId: '${widget.cell.id}:arguments',
        ),
      if (_projection.commandActions != null)
        _MobileCodexToolSection(
          label: 'Command Actions',
          value: _projection.commandActions!,
          paginationId: '${widget.cell.id}:command-actions',
        ),
      if (_projection.response != null)
        _MobileCodexToolSection(
          label: _projection.responseLabel,
          value: _projection.response!,
          paginationId: '${widget.cell.id}:response',
        ),
      if (_projection.fallback != null)
        _MobileCodexToolSection(
          label: 'Output',
          value: _projection.fallback!,
          paginationId: '${widget.cell.id}:output',
        ),
    ],
  );
}

class _MobileCodexToolProjection {
  const _MobileCodexToolProjection({
    required this.overview,
    required this.arguments,
    required this.commandActions,
    required this.response,
    required this.responseLabel,
    required this.fallback,
  });

  factory _MobileCodexToolProjection.fromCell(MobileCodexTimelineCell cell) {
    final metadata = cell.metadata;
    final arguments = _decodeMobileToolValue(metadata['arguments']);
    final commandActions = _decodeMobileToolValue(metadata['commandActions']);
    final error = _decodeMobileToolValue(metadata['error']);
    final result = _decodeMobileToolValue(metadata['result']);
    final contentItems = _decodeMobileToolValue(metadata['contentItems']);
    final results = _decodeMobileToolValue(metadata['results']);
    final changes = _decodeMobileToolValue(metadata['changes']);
    final legacyOutput = _firstMobileToolValue(<Object?>[
      _decodeMobileToolValue(metadata['aggregatedOutput']),
      _decodeMobileToolValue(metadata['output']),
      _decodeMobileToolValue(metadata['diff']),
      _decodeMobileToolValue(metadata['commandOutput']),
    ]);
    final details = _decodeMobileToolValue(cell.detailsText);
    final dynamicOutput =
        metadata['itemType']?.toString().toLowerCase() == 'dynamictoolcall'
        ? details
        : null;
    final response = _firstMobileToolValue(<Object?>[
      error,
      result,
      contentItems,
      results,
      changes,
      legacyOutput,
      dynamicOutput,
    ]);
    final query = metadata['query'];
    final action = _decodeMobileToolValue(metadata['action']);
    final effectiveArguments =
        arguments ??
        (_hasMobileToolValue(query) || _hasMobileToolValue(action)
            ? <String, Object?>{
                if (_hasMobileToolValue(query)) 'query': query,
                if (_hasMobileToolValue(action)) 'action': action,
              }
            : null);
    final markdown = _decodeMobileToolValue(
      cell.renderedMarkdownText ?? cell.markdownText,
    );
    final detailsCovered = _mobileDetailsCoveredByStructuredField(
      _mobileEffectiveDetailsSource(metadata),
      error: error,
      result: result,
      contentItems: contentItems,
      results: results,
      changes: changes,
      action: action,
    );
    final fallback = <Object?>[if (!detailsCovered) details, markdown]
        .firstWhere(
          (candidate) =>
              _hasMobileToolValue(candidate) &&
              !_sameMobileToolValue(candidate, response) &&
              !_sameMobileToolValue(candidate, effectiveArguments) &&
              !_sameMobileToolValue(candidate, action),
          orElse: () => null,
        );
    return _MobileCodexToolProjection(
      overview: <(String, String)>[
        for (final (label, value) in <(String, Object?)>[
          ('Server', metadata['server']),
          ('Tool', metadata['tool']),
          ('Namespace', metadata['namespace']),
          ('App', _mobileCodexToolAppLabel(metadata['appContext'])),
          ('URL', metadata['url']),
          ('Duration', _mobileDuration(metadata['durationMs'])),
        ])
          if (_hasMobileToolValue(value)) (label, '$value'),
      ],
      arguments: effectiveArguments,
      commandActions: commandActions,
      response: response,
      responseLabel: error != null
          ? 'Error'
          : changes != null &&
                result == null &&
                contentItems == null &&
                results == null
          ? 'Changes'
          : results != null && result == null && contentItems == null
          ? 'Results'
          : legacyOutput != null &&
                error == null &&
                result == null &&
                contentItems == null &&
                results == null &&
                changes == null
          ? 'Output'
          : 'Response',
      fallback: fallback,
    );
  }

  final List<(String, String)> overview;
  final Object? arguments;
  final Object? commandActions;
  final Object? response;
  final String responseLabel;
  final Object? fallback;
}

String? _mobileCodexToolAppLabel(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value is! Map) return null;
  for (final key in const <String>['appName', 'connectorId']) {
    final candidate = value[key];
    if (candidate is String && candidate.trim().isNotEmpty) return candidate;
  }
  return null;
}

bool _mobileDetailsCoveredByStructuredField(
  Object? source, {
  required Object? error,
  required Object? result,
  required Object? contentItems,
  required Object? results,
  required Object? changes,
  required Object? action,
}) => switch (source?.toString()) {
  'error' => _isMobileDetailsFieldPresent(error),
  'result' => _isMobileDetailsFieldPresent(result),
  'contentItems' => _isMobileDetailsFieldPresent(contentItems),
  'results' => _isMobileDetailsFieldPresent(results),
  'changes' => _isMobileDetailsFieldPresent(changes),
  'action' => _isMobileDetailsFieldPresent(action),
  _ => false,
};

String? _mobileEffectiveDetailsSource(Map<String, Object?> metadata) {
  final source = metadata['detailsSource']?.toString();
  if (source != null && source.isNotEmpty) return source;
  for (final candidate in const <String>[
    'aggregatedOutput',
    'output',
    'result',
    'error',
    'diff',
    'commandOutput',
    'changes',
    'contentItems',
    'action',
  ]) {
    if (_isMobileDetailsFieldPresent(metadata[candidate])) return candidate;
  }
  return null;
}

bool _isMobileDetailsFieldPresent(Object? value) =>
    value != null && (value is! String || value.isNotEmpty);

class _MobileCodexToolScalar extends StatelessWidget {
  const _MobileCodexToolScalar({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _MobileCodexToolSection extends StatelessWidget {
  const _MobileCodexToolSection({
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
            IconButton(
              tooltip: 'Copy $label',
              visualDensity: VisualDensity.compact,
              onPressed: () => unawaited(_copyMobileCodexToolValue(value)),
              icon: const Icon(AleraIcons.copy, size: AleraTokens.space16),
            ),
          ],
        ),
        _MobileCodexToolValue(value: value, paginationId: paginationId),
      ],
    ),
  );
}

Future<void> _copyMobileCodexToolValue(Object value) async {
  final text = await compute(_encodeMobileToolValue, value);
  await Clipboard.setData(ClipboardData(text: text));
}

Object? _decodeMobileToolValue(Object? value) {
  if (value is! String) return value;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > _mobileCodexToolTextLimit) return value;
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return value;
  }
}

Object? _firstMobileToolValue(List<Object?> values) {
  for (final value in values) {
    if (value == null || value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

bool _hasMobileToolValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

bool _sameMobileToolValue(Object? left, Object? right) {
  if (left == null || right == null) return false;
  return _MobileToolValueComparator().equals(left, right);
}

class _MobileToolValueComparator {
  var _remainingNodes = 256;

  bool equals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (_remainingNodes <= 0) return false;
    _remainingNodes -= 1;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !equals(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index += 1) {
        if (!equals(left[index], right[index])) return false;
      }
      return true;
    }
    if (left is Map || right is Map || left is List || right is List) {
      return false;
    }
    return left == right;
  }
}

String _encodeMobileToolValue(Object value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return '$value';
  }
}

String _mobileToolFieldLabel(String key) {
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
