import 'package:dart_mappable/dart_mappable.dart';

part 'pull_request_ship_follow_up.mapper.dart';

/// What the Ship split button starts once the pull request exists. Remembered
/// globally so the button keeps the last choice.
@MappableEnum()
enum PullRequestShipFollowUp {
  /// Ship only.
  none,

  /// Start Watch and Fix on the shipped pull request.
  watchAndFix,

  /// Start Watch, Fix and Merge on the shipped pull request. A draft can never
  /// merge, so this follow-up always ships a ready pull request.
  watchFixAndMerge;

  bool get watches => this != none;

  bool get merges => this == watchFixAndMerge;
}
