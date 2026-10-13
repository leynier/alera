import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_gate_card.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Stage Gate', group: 'Run Gate Card')
Widget runGateCardStagePreview() => RunGateCard(
  gate: const RunGate(
    id: 'gate-1',
    kind: RunGateKind.stage,
    status: RunGateStatus.pending,
    scope: 'foundation',
    integrationSha: '4f2a91c07d',
    evidenceDigest: 'sha256:1',
  ),
  evidence: 'Foundation integrated 3/3.',
  onDecide: (_, _) {},
  onViewEvidence: () {},
);

@AleraPreview(name: 'Stall', group: 'Run Gate Card')
Widget runGateCardStallPreview() => RunGateCard(
  gate: const RunGate(
    id: 'gate-2',
    kind: RunGateKind.stall,
    status: RunGateStatus.pending,
    options: runStallGateOptions,
  ),
  onDecide: (_, _) {},
);

@AleraPreview(name: 'Stale Plan', group: 'Run Gate Card')
Widget runGateCardStalePreview() => RunGateCard(
  gate: const RunGate(
    id: 'gate-3',
    kind: RunGateKind.plan,
    status: RunGateStatus.pending,
  ),
  stale: true,
  onDecide: (_, _) {},
  onRefresh: () {},
);
