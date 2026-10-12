import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_gate_card.dart';
import 'package:flutter/material.dart';

const List<AleraGateCardOption> _stageOptions = <AleraGateCardOption>[
  AleraGateCardOption(
    id: 'reject',
    label: 'Reject',
    destructive: true,
    requiresNotes: true,
  ),
  AleraGateCardOption(
    id: 'changes',
    label: 'Request Changes',
    requiresNotes: true,
  ),
  AleraGateCardOption(
    id: 'approve',
    label: 'Approve',
    busyLabel: 'Approving…',
    primary: true,
  ),
];

@AleraPreview(name: 'Stage gate', group: 'Gate card', size: Size(560, 340))
Widget aleraGateCardPreview() => AleraGateCard(
  kindLabel: 'Stage Gate',
  title: 'Foundation',
  statusLabel: 'Pending',
  statusDetail: 'Asked 2h ago',
  prompt: 'The foundation stage finished. Approve to start the next stage.',
  meta: 'Asked by coordinator at 13:58.',
  links: <Widget>[
    TextButton(onPressed: () {}, child: const Text('View Evidence')),
  ],
  options: _stageOptions,
  notesLabel: 'Notes (required to reject or request changes)',
  onSelected: (_, _) {},
);

@AleraPreview(name: 'Decision', group: 'Gate card', size: Size(560, 260))
Widget aleraGateCardDecisionPreview() => AleraGateCard(
  kindLabel: 'Decision',
  title: 'auth-flow',
  statusLabel: 'Pending',
  prompt: 'Which auth flow do you want for the CLI?',
  options: const <AleraGateCardOption>[
    AleraGateCardOption(id: 'device', label: 'Device Code'),
    AleraGateCardOption(id: 'pkce', label: 'PKCE'),
  ],
  allowOther: true,
  onSelected: (_, _) {},
);

@AleraPreview(name: 'Stale', group: 'Gate card', size: Size(560, 300))
Widget aleraGateCardStalePreview() => AleraGateCard(
  kindLabel: 'Plan Approval',
  title: 'Revision 2',
  statusLabel: 'Pending',
  prompt: 'Approve the revised plan before the workers start.',
  options: _stageOptions,
  stale: true,
  onRefresh: () {},
  onSelected: (_, _) {},
);
