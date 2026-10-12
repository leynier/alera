import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/infra/run_repository.dart';

/// Opens a run that needs attention on its newest due gate, or on its
/// Overview when it has none. Board rows name their due gates, so [gateId]
/// opens it directly; without one (an older host) the gates are read when
/// the link is followed.
Future<void> openRunAttention(
  RunRepository repository,
  ActivityNavigation navigation,
  String runId, {
  String? gateId,
  bool Function()? mounted,
}) async {
  if (gateId == null) {
    try {
      final gates = await repository.gates(
        runId,
        status: RunGateStatus.pending,
      );
      gateId = gates.where((gate) => gate.due).firstOrNull?.id;
    } on Object {
      gateId = null;
    }
    if (mounted != null && !mounted()) return;
  }
  if (gateId != null) {
    navigation.focusGate(runId, gateId);
  } else {
    navigation
      ..open(ActivitySection.runs)
      ..selectRun(runId);
  }
}
