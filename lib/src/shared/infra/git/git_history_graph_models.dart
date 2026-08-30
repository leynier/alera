part of 'git_diff_models.dart';

enum GitHistoryGraphColorId {
  ref,
  remoteRef,
  baseRef,
  lane1,
  lane2,
  lane3,
  lane4,
  lane5,
}

const GitHistoryGraphColorId gitHistoryRefColor = .ref;
const GitHistoryGraphColorId gitHistoryRemoteRefColor = .remoteRef;
const GitHistoryGraphColorId gitHistoryBaseRefColor = .baseRef;
const List<GitHistoryGraphColorId> gitHistoryLaneColors =
    <GitHistoryGraphColorId>[
      GitHistoryGraphColorId.lane1,
      GitHistoryGraphColorId.lane2,
      GitHistoryGraphColorId.lane3,
      GitHistoryGraphColorId.lane4,
      GitHistoryGraphColorId.lane5,
    ];
