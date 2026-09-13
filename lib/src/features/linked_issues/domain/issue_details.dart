import 'package:alera/src/features/linked_issues/domain/issue_state.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'issue_details.mapper.dart';

/// An issue as the runtime host fetched it from its forge (`issue.fetch`).
@MappableClass()
class const IssueDetails({
  required this.provider,
  required this.url,
  required this.number,
  required this.title,
  required this.state,
  this.repository,
  this.stateLabel,
  this.body,
  this.labels = const <String>[],
  this.assignees = const <String>[],
  this.author,
  this.createdAt,
  this.updatedAt,
}) with IssueDetailsMappable {
  final GitHostingProvider provider;
  final String url;
  final int number;
  final String title;
  final IssueState state;
  final String? repository;
  final String? stateLabel;
  final String? body;
  final List<String> labels;
  final List<String> assignees;
  final String? author;
  final String? createdAt;
  final String? updatedAt;

  String get displayState => stateLabel ?? state.label;

  factory fromJson(Map<String, Object?> json) =>
      IssueDetailsMapper.fromMap(Map<String, dynamic>.from(json));
}
