import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add Host step 3: the host is ready, with the way to put a project on it.
class const AddRemoteHostDoneStep({
  super.key,
  required final String hostId,
  required final VoidCallback onAddProject,
  required final VoidCallback onDone,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final host = ref.watch(
      remoteHostsControllerProvider.select((state) => state.hostById(hostId)),
    );
    final canAddProject =
        ref.watch(projectHostsSupportedProvider).value ?? false;
    final status = host?.status;
    final version = switch (status) {
      RemoteHostConnected(:final satelliteVersion?) => satelliteVersion,
      _ => host?.target.runtimeVersion,
    };
    final summary = <String>[
      version == null ? 'Alera runtime' : 'Alera runtime $version',
      ?host?.platformLabel,
      ?status?.label,
    ].join(' · ');
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const AleraStatusIndicator(
              icon: AleraIcons.success,
              color: AleraTokens.success,
            ),
            const SizedBox(width: AleraTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text(
                    '${host?.alias ?? 'The host'} is ready',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space24),
        Row(
          mainAxisAlignment: .end,
          children: <Widget>[
            if (canAddProject) ...<Widget>[
              OutlinedButton(
                onPressed: onAddProject,
                child: const Text('Add a Project to This Host'),
              ),
              const SizedBox(width: AleraTokens.space8),
            ],
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ],
    );
  }
}
