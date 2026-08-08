part of 'codex_chat_models.dart';

String codexModelDisplayLabel(String value) {
  final trimmed = value.trim();
  final match = RegExp(
    r'^gpt-(\d+(?:\.\d+)*)(?:[- ](.+))?$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) return trimmed;
  final version = match.group(1)!;
  final suffix = match.group(2);
  if (suffix == null || suffix.trim().isEmpty) return version;
  final words = suffix
      .split(RegExp(r'[- ]+'))
      .where((word) => word.isNotEmpty)
      .map(
        (word) =>
            '${word.substring(0, 1).toUpperCase()}'
            '${word.substring(1).toLowerCase()}',
      )
      .join(' ');
  return '$version $words';
}

extension CodexQuestionOptionPresentation on CodexQuestionOption {
  bool get isRecommended =>
      label.trim().toLowerCase().endsWith('(recommended)');

  String get displayLabel => isRecommended
      ? label
            .trim()
            .substring(0, label.trim().length - '(recommended)'.length)
            .trim()
      : label;
}

extension CodexPendingRequestPlanQuestion on CodexPendingRequest {
  bool get isImplementPlanQuestion {
    if (!isQuestion) return false;
    final text = <Object?>[
      params['title'],
      params['question'],
      params['prompt'],
      params['message'],
      for (final question in questions) question.question,
    ].join(' ').toLowerCase();
    return text.contains('implement') && text.contains('plan');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String? _nullableString(Iterable<Object?> values) {
  final value = _firstString(values);
  return value.isEmpty ? null : value;
}

String _firstString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return '';
}

List<String> _reasoningEfforts(Object? value) {
  if (value is! List) return const <String>[];
  final result = <String>[];
  for (final entry in value) {
    final effort = entry is Map
        ? (entry['reasoningEffort'] ??
                  entry['effort'] ??
                  entry['id'] ??
                  entry['name'])
              ?.toString()
        : entry.toString();
    if (effort != null && effort.trim().isNotEmpty) result.add(effort.trim());
  }
  return result;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

bool _containsFast(Object? value) {
  if (value is String) return value.trim().toLowerCase() == 'fast';
  if (value is Map) {
    if (<Object?>[
      value['id'],
      value['name'],
      value['tier'],
      value['slug'],
      value['serviceTier'],
    ].whereType<String>().any(
      (entry) => entry.trim().toLowerCase() == 'fast',
    )) {
      return true;
    }
    return value.values.any(_containsFast);
  }
  if (value is Iterable) return value.any(_containsFast);
  return false;
}

String _legacyKind(String method, Map<String, Object?> item) {
  final type = (item['type'] ?? '').toString().toLowerCase();
  final lower = method.toLowerCase();
  if (type.contains('user')) return 'user';
  if (type.contains('agent') || type.contains('assistant')) return 'assistant';
  if (type.contains('reason')) return 'reasoning';
  if (type.contains('command') || lower.contains('command')) return 'command';
  if (type.contains('tool') || lower.contains('tool')) return 'tool';
  if (type.contains('diff') || lower.contains('diff')) return 'diff';
  if (type.contains('plan') || lower.contains('plan')) return 'plan';
  return 'event';
}
