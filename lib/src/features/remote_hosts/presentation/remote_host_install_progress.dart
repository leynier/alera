import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_progress_steps.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:flutter/material.dart';

/// [progress] as an [AleraProgressSteps] list. Before the first progress
/// event arrives the first step shows as running.
List<AleraProgressStep> remoteHostInstallProgressSteps(
  RemoteHostInstallProgress? progress, {
  required String targetId,
}) {
  final source = progress ?? RemoteHostInstallProgress(targetId: targetId);
  return <AleraProgressStep>[
    for (final step in source.steps)
      AleraProgressStep(
        label: step.label,
        detail: step.detail,
        state: _stepState(step.state),
        progress: step.progress,
      ),
  ];
}

AleraProgressStepState _stepState(RemoteHostInstallStepState state) {
  return switch (state) {
    RemoteHostInstallStepState.pending => AleraProgressStepState.pending,
    RemoteHostInstallStepState.active => AleraProgressStepState.active,
    RemoteHostInstallStepState.done => AleraProgressStepState.done,
    RemoteHostInstallStepState.failed => AleraProgressStepState.failed,
    RemoteHostInstallStepState.skipped => AleraProgressStepState.skipped,
  };
}

/// The install steps of one host with Cancel Install, shown in the host's
/// detail while the runtime installs.
class const RemoteHostInstallProgressPanel({
  super.key,
  required final String targetId,
  required final RemoteHostInstallProgress? progress,
  required final String title,
  required final VoidCallback? onCancel,
  final bool cancelling = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  OutlinedButton(
                    onPressed: cancelling ? null : onCancel,
                    child: Text(cancelling ? 'Cancelling…' : 'Cancel Install'),
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space12),
              AleraProgressSteps(
                steps: remoteHostInstallProgressSteps(
                  progress,
                  targetId: targetId,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
