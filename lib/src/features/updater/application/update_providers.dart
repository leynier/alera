import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/updater/application/update_check_scheduler.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_providers.g.dart';

@Riverpod(keepAlive: true)
http.Client aleraUpdateHttpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
AleraUpdateService aleraUpdateService(Ref ref) {
  final service = DesktopAleraUpdateService(
    client: ref.watch(aleraUpdateHttpClientProvider),
    processRunner: ref.watch(processRunnerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}

/// The package manager that owns this installation, if any.
///
/// Read from the service so the detection stays in one place: the same value
/// decides whether an update may be auto-installed and what Settings offers.
@Riverpod(keepAlive: true)
PackageManagerInstall packageManagerInstall(Ref ref) {
  return ref.watch(aleraUpdateServiceProvider).packageInstall;
}

/// Nothing reads this provider's value: mounting it is what starts the
/// recurring check, so the app shell watches it to keep it alive.
@Riverpod(keepAlive: true)
AleraUpdateCheckScheduler aleraUpdateCheckScheduler(Ref ref) {
  final scheduler = AleraUpdateCheckScheduler(
    check: ref.read(aleraUpdateControllerProvider.notifier).checkForUpdates,
    foreground: ref.watch(appForegroundProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
}
