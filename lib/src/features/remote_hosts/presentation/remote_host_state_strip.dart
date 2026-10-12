import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_install_progress.dart';
import 'package:flutter/material.dart';

const String remoteHostNeedsSetupMessage =
    'The Alera runtime is not installed on this host yet. Installing it lets Alera open terminals, files and Git there.';

String remoteHostUpdateAvailableMessage(RemoteHostConnected status) {
  final available = status.hubVersion;
  final current = status.satelliteVersion;
  if (available == null || current == null) {
    return 'A newer Alera runtime is available for this host.';
  }
  return 'Alera runtime $available is available for this host. The current version is $current.';
}

/// What the host's state asks of the user, under the header: install it,
/// follow the install, recover from an error, or update the runtime. Also
/// shows the last failed action, such as a refused Remove Host. Renders
/// nothing, gap included, for a settled host.
class const RemoteHostStateStrip({
  super.key,
  required final RemoteHostView host,
  required final RemoteHostCapabilities capabilities,
  required final VoidCallback onInstall,
  required final VoidCallback onCancelInstall,
  required final VoidCallback onRetry,
  required final ValueChanged<String> onCopyError,
  required final VoidCallback onUpdateRuntime,
  required final VoidCallback onDismissError,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = host.status;
    final stateNotice = _stateNotice(status);
    final actionError = host.actionError;
    final showActionError =
        actionError != null &&
        !(status is RemoteHostError && status.detail == actionError);
    if (stateNotice == null && !showActionError) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          ?stateNotice,
          if (stateNotice != null && showActionError)
            const SizedBox(height: AleraTokens.space12),
          if (showActionError)
            AleraInlineNotice(
              message: actionError,
              tone: .error,
              child: Wrap(
                spacing: AleraTokens.space8,
                children: <Widget>[
                  TextButton(
                    onPressed: () => onCopyError(actionError),
                    child: const Text('Copy Error'),
                  ),
                  TextButton(
                    onPressed: onDismissError,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? _stateNotice(RemoteHostStatus status) {
    switch (status) {
      case RemoteHostNeedsSetup():
        return AleraInlineNotice(
          message: remoteHostNeedsSetupMessage,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: host.busy ? null : onInstall,
              child: const Text('Install Runtime'),
            ),
          ),
        );
      case RemoteHostInstalling():
        return RemoteHostInstallProgressPanel(
          targetId: host.id,
          progress: host.installProgress,
          title: 'Installing Alera runtime on ${host.alias}',
          cancelling: host.busy,
          onCancel: onCancelInstall,
        );
      case RemoteHostError(:final detail, :final origin):
        final canRetry =
            origin == RemoteHostErrorOrigin.install || capabilities.hostLinks;
        return AleraInlineNotice(
          message: detail,
          tone: .error,
          child: Wrap(
            spacing: AleraTokens.space8,
            children: <Widget>[
              if (canRetry)
                FilledButton(
                  onPressed: host.busy ? null : onRetry,
                  child: const Text('Retry'),
                ),
              TextButton(
                onPressed: () => onCopyError(detail),
                child: const Text('Copy Error'),
              ),
            ],
          ),
        );
      case final RemoteHostConnected connected when connected.updateAvailable:
        return AleraInlineNotice(
          message: remoteHostUpdateAvailableMessage(connected),
          child: capabilities.runtimeUpdate
              ? Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    onPressed: host.busy ? null : onUpdateRuntime,
                    child: const Text('Update Runtime'),
                  ),
                )
              : null,
        );
      default:
        return null;
    }
  }
}
