import 'package:alera_mobile/src/core/json_payload_fields.dart';

/// The issue a workspace was created for, as the runtime stores it. The URL is
/// the source of truth; [title] and [state] cache the last successful fetch.
class const MobileLinkedIssue({
  required final String workspaceId,
  required final String url,
  final String? provider,
  final int? number,
  final String? title,
  final String? state,
  final String? stateLabel,
  final String? fetchError,
}) {
  factory MobileLinkedIssue.fromJson(Map<String, Object?> json) =>
      MobileLinkedIssue(
        workspaceId: json.requiredString('workspaceId'),
        url: json.requiredString('url'),
        provider: json.optionalString('provider'),
        number: json.optionalPositiveInt('number'),
        title: json.optionalString('title'),
        state: json.optionalString('state'),
        stateLabel: json.optionalString('stateLabel'),
        fetchError: json.optionalString('fetchError'),
      );

  bool get isFetchable => provider != null && number != null;

  /// `#758` when the number is known, otherwise the URL itself.
  String get reference => number == null ? url : '#$number';

  String? get displayState => stateLabel ?? _stateLabel(state);

  bool get isOpen => state == 'open';

  bool get isClosed => state == 'closed';
}

/// An issue fetched by the runtime through its forge CLI (`issue.fetch`).
class const MobileIssueDetails({
  required final String url,
  required final int number,
  required final String title,
  required final String state,
  final String? stateLabel,
  final String? body,
}) {
  factory MobileIssueDetails.fromJson(Map<String, Object?> json) =>
      MobileIssueDetails(
        url: json.requiredString('url'),
        number: json.requiredInt('number'),
        title: json.optionalString('title') ?? '',
        state: json.optionalString('state') ?? 'unknown',
        stateLabel: json.optionalString('stateLabel'),
        body: json.optionalString('body'),
      );

  String get displayState => stateLabel ?? _stateLabel(state) ?? 'Unknown';
}

/// What `linkedIssue.link` answers: the stored link, plus why the issue could
/// not be read when that failed. The link is kept either way.
class const MobileLinkIssueResult({
  required final MobileLinkedIssue linkedIssue,
  final String? fetchErrorCode,
  final String? fetchErrorMessage,
}) {
  factory MobileLinkIssueResult.fromJson(Map<String, Object?> json) {
    final error = json.mapValue('fetchError');
    return MobileLinkIssueResult(
      linkedIssue: MobileLinkedIssue.fromJson(json.mapValue('linkedIssue')),
      fetchErrorCode: error.optionalString('code'),
      fetchErrorMessage: error.optionalString('message'),
    );
  }
}

/// Host support plus every link keyed by workspace id.
class const MobileLinkedIssueSnapshot({
  final bool supported = false,
  final Map<String, MobileLinkedIssue> byWorkspace =
      const <String, MobileLinkedIssue>{},
});

/// Runtime surface for linked issues, feature-detected through
/// `linkedIssuesV1` in the `mobile.hello` capabilities.
abstract interface class MobileLinkedIssueClient {
  bool get supportsLinkedIssues;
  Future<List<MobileLinkedIssue>> listLinkedIssues();
  Future<MobileLinkIssueResult> linkIssue(String workspaceId, String url);
  Future<void> unlinkIssue(String workspaceId);
  Future<MobileIssueDetails> fetchIssue(String url);
}

String? _stateLabel(String? state) => switch (state) {
  'open' => 'Open',
  'closed' => 'Closed',
  _ => null,
};
