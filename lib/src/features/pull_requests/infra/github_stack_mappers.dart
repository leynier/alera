import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';

/// Maps the GitHub stacks REST response into the provider-neutral domain model.
HostedReviewStack mapGitHubStack(
  Map<String, Object?> json, {
  required String repositoryUrl,
}) {
  final rawReviews = json['pull_requests'];
  final reviewMaps = rawReviews is List
      ? rawReviews.whereType<Map>().map(
          (entry) => Map<String, Object?>.from(entry),
        )
      : const Iterable<Map<String, Object?>>.empty();
  final entries = <HostedReviewStackEntry>[];
  for (final (index, reviewJson) in reviewMaps.indexed) {
    entries.add(
      HostedReviewStackEntry(
        review: _mapGitHubStackReview(reviewJson, repositoryUrl: repositoryUrl),
        position: index + 1,
      ),
    );
  }
  final base = _objectMap(json['base']);
  return HostedReviewStack(
    number: _intValue(json['number']),
    baseBranch: _stringValue(base?['ref']) ?? '',
    open: json['open'] as bool? ?? false,
    createdAt: _parseDate(json['created_at']),
    entries: entries,
  );
}

HostedReview _mapGitHubStackReview(
  Map<String, Object?> json, {
  required String repositoryUrl,
}) {
  final number = _intValue(json['number']);
  final head = _objectMap(json['head']);
  final base = _objectMap(json['base']);
  final user = _objectMap(json['user']);
  final headBranch = _stringValue(head?['ref']);
  final mergedAt = _parseDate(json['merged_at']);
  final rawState = (_stringValue(json['state']) ?? 'open').toLowerCase();
  final draft = json['draft'] as bool? ?? false;
  final state = mergedAt != null
      ? HostedReviewState.merged
      : switch (rawState) {
          'closed' => HostedReviewState.closed,
          _ => draft ? HostedReviewState.draft : HostedReviewState.open,
        };
  return HostedReview(
    provider: .github,
    number: number,
    title: _stringValue(json['title']) ?? headBranch ?? 'Pull Request #$number',
    state: state,
    url: _stringValue(json['html_url']) ?? '$repositoryUrl/pull/$number',
    createdAt: _parseDate(json['created_at']),
    author: _stringValue(user?['login']),
    baseBranch: _stringValue(base?['ref']),
    headBranch: headBranch,
    headSha: _stringValue(head?['sha']),
  );
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return Map<String, Object?>.from(value);
}

int _intValue(Object? value) => value is num ? value.toInt() : 0;

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
