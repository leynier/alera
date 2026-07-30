import 'package:alera/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera/src/features/diagnostics/infra/diagnostics_service.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/shared/infra/logging/app_logger.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diagnostics_providers.g.dart';

@Riverpod(keepAlive: true)
DiagnosticsService diagnosticsService(Ref ref) => DiagnosticsService();

Level loggingLevelFor(DiagnosticsLogLevel level) {
  return switch (level) {
    DiagnosticsLogLevel.error => Level.SEVERE,
    DiagnosticsLogLevel.warning => Level.WARNING,
    DiagnosticsLogLevel.info => Level.INFO,
    DiagnosticsLogLevel.debug => Level.FINE,
  };
}

/// Applies the stored diagnostics settings to the live logger and to crash
/// reporting.
///
/// Settings load after startup, so the values chosen at boot are defaults; this
/// is what makes the user's actual choice take effect, and it re-runs on every
/// change so turning reporting off stops it immediately.
@Riverpod(keepAlive: true)
void diagnosticsSettingsApplier(Ref ref) {
  var diagnostics = DiagnosticsSettings.defaults;
  if (ref.watch(aleraDatabaseProvider).hasValue) {
    try {
      diagnostics = ref.watch(
        settingsControllerProvider.select((settings) => settings.diagnostics),
      );
    } on Object {
      // Diagnostics must never be the reason the app cannot start. Keep the safe
      // defaults and let the shell surface the settings failure.
    }
  }
  AppLogger.setLevel(loggingLevelFor(diagnostics.logLevel));
  CrashReporting.setEnabled(diagnostics.crashReportingEnabled);
}

/// Runtime facts for the bundle, read from a live host.
///
/// A host that is down, or one older than `hostDiagnosticsLogsV1`, yields an
/// info with no log directory rather than an error: a bundle without the
/// runtime section is still the most useful thing available at that point.
@riverpod
Future<RuntimeDiagnosticsInfo> runtimeDiagnosticsInfo(Ref ref) async {
  final client = ref.watch(runtimeHostClientProvider);
  try {
    final status = await client.probeRuntimeStatus();
    if (status == null) {
      return const RuntimeDiagnosticsInfo();
    }
    return RuntimeDiagnosticsInfo(
      version: status['runtimeHostVersion'] as String?,
      commit: status['runtimeHostCommit'] as String?,
      protocolVersion: status['protocolVersion'] as int?,
      logDirectory: status['logDirectory'] as String?,
      capabilities: <String>[
        ...?(status['runtimeCapabilities'] as List<Object?>?)
            ?.whereType<String>(),
      ],
    );
  } on Object {
    return const RuntimeDiagnosticsInfo();
  }
}
