import 'package:alera/src/features/linked_issues/domain/issue_state.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'linked_issue.mapper.dart';

/// The issue a workspace was created for, persisted by the runtime host. The
/// URL is the source of truth: [provider], [repository] and [number] are only
/// set when a provider recognized it, and [title]/[state] cache the last
/// successful fetch so the sidebar renders without a network call.
@MappableClass()
class const LinkedIssue({
  required this.workspaceId,
  required this.url,
  required this.linkedAt,
  this.provider,
  this.repository,
  this.number,
  this.title,
  this.state,
  this.stateLabel,
  this.fetchedAt,
  this.fetchError,
}) with LinkedIssueMappable {
  final String workspaceId;
  final String url;
  final GitHostingProvider? provider;
  final String? repository;
  final int? number;
  final String? title;
  final IssueState? state;
  final String? stateLabel;
  final DateTime? fetchedAt;
  final String? fetchError;
  final DateTime linkedAt;

  /// Whether a provider can fetch this issue; URL-only links cannot.
  bool get isFetchable => provider != null && number != null;

  /// `#758` when the number is known, otherwise the URL itself.
  String get reference => number == null ? url : '#$number';

  /// The forge's wording when it has one, otherwise the neutral state.
  String? get displayState => stateLabel ?? state?.label;

  factory fromJson(Map<String, Object?> json) =>
      LinkedIssueMapper.fromMap(Map<String, dynamic>.from(json));
}
