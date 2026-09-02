import 'dart:convert';

import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_summary.dart';

class const WorkspacePullRequestFailure({
  required this.workspaceId,
  required this.summary,
}) {
  final String workspaceId;
  final WorkspacePullRequestSummary summary;
}

/// Emits only transitions into a failed-check state. Clearing the failure
/// removes its dedupe key, so a later failing run on the same PR can notify.
class WorkspacePullRequestFailureTracker {
  final Map<String, String> _activeFailureSignatures = <String, String>{};
  bool _baselined = false;

  void baseline(Map<String, WorkspacePullRequestSummary> summaries) {
    _activeFailureSignatures
      ..clear()
      ..addEntries(_failureEntries(summaries));
    _baselined = true;
  }

  List<WorkspacePullRequestFailure> pending(
    Map<String, WorkspacePullRequestSummary> summaries,
  ) {
    if (!_baselined) {
      baseline(summaries);
      return const <WorkspacePullRequestFailure>[];
    }
    final current = <String, String>{
      for (final entry in _failureEntries(summaries)) entry.key: entry.value,
    };
    final failures = <WorkspacePullRequestFailure>[];
    for (final entry in current.entries) {
      if (_activeFailureSignatures[entry.key] == entry.value) {
        continue;
      }
      failures.add(
        WorkspacePullRequestFailure(
          workspaceId: entry.key,
          summary: summaries[entry.key]!,
        ),
      );
    }
    _activeFailureSignatures
      ..clear()
      ..addAll(current);
    return failures;
  }

  void reset() {
    _activeFailureSignatures.clear();
    _baselined = false;
  }

  Iterable<MapEntry<String, String>> _failureEntries(
    Map<String, WorkspacePullRequestSummary> summaries,
  ) sync* {
    for (final entry in summaries.entries) {
      final summary = entry.value;
      if (!summary.checksFailed ||
          summary.review.state == HostedReviewState.merged ||
          summary.review.state == HostedReviewState.closed) {
        continue;
      }
      yield MapEntry<String, String>(
        entry.key,
        <Object?>[summary.review.number, summary.review.headSha].join(':'),
      );
    }
  }
}

class const WorkspacePullRequestNotificationPayload({
  required this.workspaceId,
  required this.reviewNumber,
  required this.reviewUrl,
}) {
  final String workspaceId;
  final int reviewNumber;
  final String reviewUrl;

  String encode() => jsonEncode(<String, Object?>{
    'kind': 'pullRequestChecksFailed',
    'workspaceId': workspaceId,
    'reviewNumber': reviewNumber,
    'reviewUrl': reviewUrl,
  });
}

WorkspacePullRequestNotificationPayload?
decodeWorkspacePullRequestNotificationPayload(String? payload) {
  if (payload == null || payload.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      return null;
    }
    final record = Map<String, Object?>.from(decoded);
    if (record['kind'] != 'pullRequestChecksFailed') {
      return null;
    }
    final workspaceId = record['workspaceId'];
    final reviewNumber = record['reviewNumber'];
    final reviewUrl = record['reviewUrl'];
    if (workspaceId is! String ||
        workspaceId.isEmpty ||
        reviewNumber is! num ||
        reviewUrl is! String ||
        reviewUrl.isEmpty) {
      return null;
    }
    return WorkspacePullRequestNotificationPayload(
      workspaceId: workspaceId,
      reviewNumber: reviewNumber.toInt(),
      reviewUrl: reviewUrl,
    );
  } catch (_) {
    return null;
  }
}

AgentStatusNotification composeWorkspacePullRequestFailureNotification({
  required WorkspacePullRequestFailure failure,
  String? projectName,
  String? workspaceName,
}) {
  final summary = failure.summary;
  final names = summary.failingCheckNames.join(', ');
  final hidden = summary.failedCheckCount - summary.failingCheckNames.length;
  final failedChecks = names.isEmpty
      ? '${summary.failedCheckCount} checks failed'
      : hidden > 0
      ? '$names, +$hidden more'
      : names;
  final project = projectName?.trim() ?? '';
  final workspace = workspaceName?.trim() ?? '';
  final location = <String>[
    if (project.isNotEmpty) project,
    if (workspace.isNotEmpty && workspace != project) workspace,
  ].join(' · ');
  return AgentStatusNotification(
    id: _fnv1a(
      '${failure.workspaceId}|${summary.review.number}|${summary.review.headSha}',
    ),
    title: 'PR #${summary.review.number} checks failed',
    body: location.isEmpty ? failedChecks : '$location — $failedChecks',
    payload: WorkspacePullRequestNotificationPayload(
      workspaceId: failure.workspaceId,
      reviewNumber: summary.review.number,
      reviewUrl: summary.review.url,
    ).encode(),
  );
}

int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? 1 : hash;
}
