part of 'codex_chat_surface.dart';

class _CodexToolDetailsProjection {
  const _CodexToolDetailsProjection({
    required this.overview,
    required this.arguments,
    required this.commandActions,
    required this.response,
    required this.responseLabel,
    required this.images,
    required this.details,
    required this.showDetails,
    required this.isDiff,
    required this.diffLines,
  });

  factory _CodexToolDetailsProjection.fromCell(CodexTimelineCell cell) {
    final metadata = cell.metadata;
    final details = cell.detailsText ?? cell.markdownText ?? '';
    final arguments = _decodeCodexStructuredValue(metadata['arguments']);
    final commandActions = _decodeCodexStructuredValue(
      metadata['commandActions'],
    );
    final error = _decodeCodexStructuredValue(metadata['error']);
    final result = _decodeCodexStructuredValue(metadata['result']);
    final contentItems = _decodeCodexStructuredValue(metadata['contentItems']);
    final results = _decodeCodexStructuredValue(metadata['results']);
    final changes = _decodeCodexStructuredValue(metadata['changes']);
    final legacyOutput = _firstCodexStructuredValue(<Object?>[
      _decodeCodexStructuredValue(metadata['aggregatedOutput']),
      _decodeCodexStructuredValue(metadata['output']),
      _decodeCodexStructuredValue(metadata['diff']),
      _decodeCodexStructuredValue(metadata['commandOutput']),
    ]);
    final decodedDetails = _decodeCodexStructuredValue(details);
    final dynamicOutput =
        metadata['itemType']?.toString().toLowerCase() == 'dynamictoolcall'
        ? decodedDetails
        : null;
    final response = _firstCodexStructuredValue(<Object?>[
      error,
      result,
      contentItems,
      results,
      changes,
      legacyOutput,
      dynamicOutput,
    ]);
    final responseLabel = error != null
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
        : 'Response';
    final query = metadata['query'];
    final action = _decodeCodexStructuredValue(metadata['action']);
    final effectiveArguments =
        arguments ??
        (_hasCodexStructuredValue(query) || _hasCodexStructuredValue(action)
            ? <String, Object?>{
                if (_hasCodexStructuredValue(query)) 'query': query,
                if (_hasCodexStructuredValue(action)) 'action': action,
              }
            : null);
    final overview = <(String, String)>[
      for (final (label, value) in <(String, Object?)>[
        ('Server', metadata['server']),
        ('Tool', metadata['tool']),
        ('Namespace', metadata['namespace']),
        ('App', _codexToolAppLabel(metadata['appContext'])),
        ('URL', metadata['url']),
        ('Duration', _codexDurationLabel(metadata['durationMs'])),
      ])
        if (_hasCodexStructuredValue(value)) (label, '$value'),
    ];
    final isDiff =
        cell.kind == CodexTimelineKind.diff || _looksLikeDiff(details);
    final detailsCovered = _codexDetailsCoveredByStructuredField(
      _codexEffectiveDetailsSource(metadata),
      error: error,
      result: result,
      contentItems: contentItems,
      results: results,
      changes: changes,
      action: action,
    );
    final showDetails =
        details.trim().isNotEmpty &&
        !detailsCovered &&
        (isDiff ||
            !_sameCodexStructuredValue(decodedDetails, response) &&
                !_sameCodexStructuredValue(
                  decodedDetails,
                  effectiveArguments,
                ) &&
                !_sameCodexStructuredValue(decodedDetails, action));
    return _CodexToolDetailsProjection(
      overview: List<(String, String)>.unmodifiable(overview),
      arguments: effectiveArguments,
      commandActions: commandActions,
      response: response,
      responseLabel: responseLabel,
      images: List<String>.unmodifiable(
        _codexDetailImages(<Object?>[details, ...metadata.values]),
      ),
      details: details,
      showDetails: showDetails,
      isDiff: isDiff,
      diffLines: isDiff
          ? List<String>.unmodifiable(details.split('\n'))
          : const <String>[],
    );
  }

  final List<(String, String)> overview;
  final Object? arguments;
  final Object? commandActions;
  final Object? response;
  final String responseLabel;
  final List<String> images;
  final String details;
  final bool showDetails;
  final bool isDiff;
  final List<String> diffLines;
}

String? _codexToolAppLabel(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value is! Map) return null;
  for (final key in const <String>['appName', 'connectorId']) {
    final candidate = value[key];
    if (candidate is String && candidate.trim().isNotEmpty) return candidate;
  }
  return null;
}

bool _codexDetailsCoveredByStructuredField(
  Object? source, {
  required Object? error,
  required Object? result,
  required Object? contentItems,
  required Object? results,
  required Object? changes,
  required Object? action,
}) => switch (source?.toString()) {
  'error' => _isCodexDetailsFieldPresent(error),
  'result' => _isCodexDetailsFieldPresent(result),
  'contentItems' => _isCodexDetailsFieldPresent(contentItems),
  'results' => _isCodexDetailsFieldPresent(results),
  'changes' => _isCodexDetailsFieldPresent(changes),
  'action' => _isCodexDetailsFieldPresent(action),
  _ => false,
};

String? _codexEffectiveDetailsSource(Map<String, Object?> metadata) {
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
    if (_isCodexDetailsFieldPresent(metadata[candidate])) return candidate;
  }
  return null;
}

bool _isCodexDetailsFieldPresent(Object? value) =>
    value != null && (value is! String || value.isNotEmpty);

Object? _decodeCodexStructuredValue(Object? value) {
  if (value is! String) return value;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > _codexStructuredToolTextLimit) return value;
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return value;
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return value;
  }
}

Object? _firstCodexStructuredValue(List<Object?> values) {
  for (final value in values) {
    if (value == null || value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

bool _hasCodexStructuredValue(Object? value) {
  if (value == null) return false;
  if (value is String) return value.trim().isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

bool _sameCodexStructuredValue(Object? left, Object? right) {
  if (left == null || right == null) return false;
  return _CodexStructuredValueComparator().equals(left, right);
}

class _CodexStructuredValueComparator {
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
