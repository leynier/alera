import 'dart:async';

import 'package:alera/src/app/app_navigation.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_link_toasts.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_visible_host.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Announces dropped and recovered host links, and installs that finished
/// out of sight, as toasts. Call from a long-lived widget's build; [policy]
/// must live as long as that widget so it remembers what it announced.
void listenRemoteHostLinkToasts(
  WidgetRef ref,
  RemoteHostLinkToastPolicy policy,
) {
  ref.listen(remoteHostsControllerProvider, (previous, next) {
    final visibleHostId = ref.read(remoteHostsVisibleHostProvider);
    if (previous != null && !policy.hasSnapshot) {
      // `WidgetRef.listen` cannot fire immediately, so the state the shell
      // first saw becomes the silent baseline here.
      policy.evaluate(
        previous.hosts.map(RemoteHostLinkSnapshot.fromView),
        visibleHostId: visibleHostId,
      );
    }
    final toasts = <RemoteHostLinkToast>[
      ...policy.evaluate(
        next.hosts.map(RemoteHostLinkSnapshot.fromView),
        visibleHostId: visibleHostId,
      ),
      ...remoteHostInstallCompletionToasts(previous, next),
    ];
    for (final toast in toasts) {
      publishRemoteHostToast(toast);
    }
  });
}

void publishRemoteHostToast(RemoteHostLinkToast toast) {
  final actionLabel = toast.actionLabel;
  AleraToast.publish(
    message: toast.message,
    tone: switch (toast.tone) {
      RemoteHostToastTone.success => .success,
      RemoteHostToastTone.warning => .warning,
      RemoteHostToastTone.error => .error,
    },
    duration: toast.long ? AleraToast.longDuration : null,
    actionLabel: actionLabel,
    onAction: actionLabel == null
        ? null
        : () {
            final context = aleraNavigatorKey.currentContext;
            if (context != null) {
              unawaited(openRemoteHostSettings(context, hostId: toast.hostId));
            }
          },
  );
}
