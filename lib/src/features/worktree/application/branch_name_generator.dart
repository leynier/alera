import 'dart:async';

abstract interface class BranchNameResolver {
  Future<String> generate({
    required String firstPrompt,
    required DateTime now,
    Duration timeout,
  });
}

class BranchNameGenerator implements BranchNameResolver {
  BranchNameGenerator({
    Future<String?> Function(String firstPrompt, Duration timeout)? aiSuggestion,
  }) : _aiSuggestion = aiSuggestion;

  final Future<String?> Function(String firstPrompt, Duration timeout)? _aiSuggestion;

  @override
  Future<String> generate({
    required String firstPrompt,
    required DateTime now,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_aiSuggestion != null) {
      try {
        final candidate = await _aiSuggestion(firstPrompt, timeout);
        final sanitized = _sanitize(candidate);
        if (sanitized != null && sanitized.isNotEmpty) {
          return 'alera/$sanitized';
        }
      } catch (_) {
        // Fallback below.
      }
    }

    final fallbackSlug = _slug(firstPrompt);
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'alera/$fallbackSlug-$timestamp';
  }

  String _slug(String prompt) {
    final normalized = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (normalized.isEmpty) {
      return 'session';
    }

    return normalized.length <= 30 ? normalized : normalized.substring(0, 30);
  }

  String? _sanitize(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9/_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^/|/$'), '');

    return normalized.isEmpty ? null : normalized;
  }
}
