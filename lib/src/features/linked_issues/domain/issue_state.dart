import 'package:dart_mappable/dart_mappable.dart';

part 'issue_state.mapper.dart';

/// Provider-neutral lifecycle of an issue. The forge's own wording (Azure
/// DevOps states such as `Active` or `Resolved`) travels separately as a label.
@MappableEnum()
enum IssueState {
  open,
  closed,
  unknown;

  String get label => switch (this) {
    IssueState.open => 'Open',
    IssueState.closed => 'Closed',
    IssueState.unknown => 'Unknown',
  };
}
