import 'package:alera/src/features/pull_requests/application/forge_exception.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';

const _invalidMergeMethodsPayload =
    'GitHub returned an invalid merge-method payload.';

/// Maps `gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`.
///
/// Null when the payload does not actually describe merge permissions, so the
/// caller can fail closed instead of advertising every GitHub method. An empty
/// list means GitHub reported every method as disabled.
List<ReviewMergeMethod>? mapGitHubRepoAllowedMergeMethods(
  Map<String, Object?> json,
) {
  final mergeCommitAllowed = _optionalBool(json['mergeCommitAllowed']);
  final squashMergeAllowed = _optionalBool(json['squashMergeAllowed']);
  final rebaseMergeAllowed = _optionalBool(json['rebaseMergeAllowed']);
  if (mergeCommitAllowed == null ||
      squashMergeAllowed == null ||
      rebaseMergeAllowed == null) {
    return null;
  }
  return <ReviewMergeMethod>[
    if (mergeCommitAllowed) ReviewMergeMethod.mergeCommit,
    if (squashMergeAllowed) ReviewMergeMethod.squash,
    if (rebaseMergeAllowed) ReviewMergeMethod.rebase,
  ];
}

bool? _optionalBool(Object? value) {
  return value is bool ? value : null;
}

/// Intersects `allowed_merge_methods` from active branch rules.
///
/// Returns null when no rule constrains merge methods, so repository settings
/// remain the authority. Multiple rules intersect: a method must appear in
/// every declared list. Malformed payloads throw so callers fail closed.
Set<ReviewMergeMethod>? mapGitHubRulesetAllowedMergeMethods(Object? decoded) {
  final entries = _flattenRuleEntries(decoded);
  Set<ReviewMergeMethod>? allowed;
  for (final entry in entries) {
    final methods = _allowedMergeMethodsFromRule(entry);
    if (methods == null) {
      continue;
    }
    allowed = allowed == null ? methods : allowed.intersection(methods);
  }
  return allowed;
}

List<Map<String, Object?>> _flattenRuleEntries(Object? decoded) {
  if (decoded == null) {
    throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
  }
  final entries = <Map<String, Object?>>[];
  void collect(Object? value) {
    if (value is Map<String, Object?>) {
      entries.add(value);
      return;
    }
    if (value is Map) {
      entries.add(Map<String, Object?>.from(value));
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item);
      }
      return;
    }
    throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
  }

  collect(decoded);
  return entries;
}

Set<ReviewMergeMethod>? _allowedMergeMethodsFromRule(
  Map<String, Object?> rule,
) {
  final type = (rule['type'] as String? ?? '').toLowerCase();
  final parameters = _asStringKeyedMap(rule['parameters']);
  if (rule.containsKey('parameters') &&
      rule['parameters'] != null &&
      parameters == null) {
    throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
  }
  if (type == 'pull_request' || type == 'merge_method') {
    return _parseAllowedMergeMethods(
      parameters?['allowed_merge_methods'],
      required: true,
    );
  }
  return _parseAllowedMergeMethods(rule['allowed_merge_methods']);
}

Set<ReviewMergeMethod>? _parseAllowedMergeMethods(
  Object? raw, {
  bool required = false,
}) {
  if (raw == null) {
    if (required) {
      throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
    }
    return null;
  }
  if (raw is! List) {
    throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
  }
  return <ReviewMergeMethod>{
    for (final item in raw) ?_mergeMethodFromToken(item),
  };
}

ReviewMergeMethod? _mergeMethodFromToken(Object? raw) {
  if (raw is! String) {
    throw const ForgeRequestFailed(_invalidMergeMethodsPayload);
  }
  final token = raw.trim().toLowerCase();
  return switch (token) {
    'merge' || 'merge_commit' || 'mergecommit' => ReviewMergeMethod.mergeCommit,
    'squash' => ReviewMergeMethod.squash,
    'rebase' => ReviewMergeMethod.rebase,
    _ => null,
  };
}

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}
