import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_job_card.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Running', group: 'Job card', size: Size(420, 160))
Widget aleraJobCardRunningPreview() => const AleraJobCard(
  title: 'Creating workspace "feature/coverage"',
  status: .running,
  phase: 'Creating workspace',
);

@AleraPreview(name: 'Failed', group: 'Job card', size: Size(420, 200))
Widget aleraJobCardFailedPreview() => AleraJobCard(
  title: 'Creating workspace "feature/coverage"',
  status: .failed,
  error: 'The branch already exists.',
  onRetry: () {},
  onDismiss: () {},
);

@AleraPreview(name: 'Clone progress', group: 'Job card', size: Size(420, 180))
Widget aleraJobCardClonePreview() => AleraJobCard(
  title: 'Cloning repository',
  status: .running,
  phase: 'Cloning repository',
  progress: 0.42,
  onCancel: () {},
);
