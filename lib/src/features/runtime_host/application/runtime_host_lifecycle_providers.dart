import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/foreground_parked_refresh.dart';
import 'package:alera/src/features/workbench/application/terminal_host_settings_config.dart';
import 'package:alera/src/features/runtime_host/application/runtime_host_lifecycle_service.dart';
import 'package:alera/src/features/runtime_host/domain/runtime_host_status.dart';
import 'package:alera/src/features/runtime_host/infra/bundled_sidecar_version_probe.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_host_lifecycle_providers.g.dart';

@Riverpod(keepAlive: true)
BundledSidecarVersionProbe bundledSidecarVersionProbe(Ref ref) {
  return ProcessBundledSidecarVersionProbe();
}

@Riverpod(keepAlive: true)
RuntimeHostLifecycleService runtimeHostLifecycleService(Ref ref) {
  return RuntimeHostLifecycleService(
    client: SocketRuntimeHostLifecycleClient(
      ref.watch(runtimeHostClientProvider),
    ),
    bundledVersionProbe: ref.watch(bundledSidecarVersionProbeProvider),
    readConfig: () {
      final settings = ref.read(settingsControllerProvider);
      return terminalHostConfigFor(
        settings.terminal,
        crashReporting: settings.diagnostics.crashReportingEnabled,
      );
    },
  );
}

@Riverpod(keepAlive: true)
Future<RuntimeHostStatusSnapshot> runtimeHostStatus(Ref ref) async {
  final service = ref.watch(runtimeHostLifecycleServiceProvider);
  final client = ref.watch(runtimeHostClientProvider);
  final foreground = ref.watch(appForegroundProvider);
  // Keep status in sync after the shell warms the host.
  ref.watch(terminalHostWarmupCoordinatorProvider);
  final sub = client.runtimeEvents.listen((event) {
    if (event.name == aleraRuntimeHostConnectedEvent) {
      ref.invalidateSelf();
    }
  });
  // Park the recurring status probe while the window is hidden: each tick is
  // an RPC nobody can see the result of. Connection events still refresh, and
  // returning to a visible window refreshes immediately.
  final poll = ForegroundParkedRefresh(
    foreground: foreground,
    interval: const Duration(seconds: 15),
    refresh: ref.invalidateSelf,
  );
  ref.onDispose(() {
    poll.dispose();
    unawaited(sub.cancel());
  });
  return service.loadStatus();
}
