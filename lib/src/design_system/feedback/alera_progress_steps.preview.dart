import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_progress_steps.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Running', group: 'Progress steps', size: Size(420, 240))
Widget aleraProgressStepsRunningPreview() => const SizedBox(
  width: 380,
  child: AleraProgressSteps(
    steps: <AleraProgressStep>[
      AleraProgressStep(label: 'Authenticate', state: .done),
      AleraProgressStep(label: 'Detect platform', state: .done),
      AleraProgressStep(label: 'Resolve runtime artifact', state: .done),
      AleraProgressStep(
        label: 'Upload runtime',
        detail: 'Uploading Runtime Artifact',
        state: .active,
        progress: 0.4,
      ),
      AleraProgressStep(label: 'Install runtime'),
      AleraProgressStep(label: 'Validate runtime'),
    ],
  ),
);

@AleraPreview(name: 'Failed', group: 'Progress steps', size: Size(420, 200))
Widget aleraProgressStepsFailedPreview() => const SizedBox(
  width: 380,
  child: AleraProgressSteps(
    dense: true,
    steps: <AleraProgressStep>[
      AleraProgressStep(label: 'Authenticate', state: .done),
      AleraProgressStep(
        label: 'Detect platform',
        detail: 'SSH authentication failed; verify ssh-agent and key config.',
        state: .failed,
      ),
      AleraProgressStep(label: 'Upload runtime', state: .skipped),
      AleraProgressStep(label: 'Install runtime'),
    ],
  ),
);
