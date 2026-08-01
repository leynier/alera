import 'dart:typed_data';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/diagnostics/application/diagnostics_providers.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Diagnostics controls: where logs live, how to export them, and whether
/// crashes are reported.
class DiagnosticsSettingsSection extends ConsumerWidget {
  const DiagnosticsSettingsSection({super.key, required this.diagnostics});

  final DiagnosticsSettings diagnostics;

  static String logLevelLabel(DiagnosticsLogLevel level) {
    return switch (level) {
      DiagnosticsLogLevel.error => 'Errors only',
      DiagnosticsLogLevel.warning => 'Warnings',
      DiagnosticsLogLevel.info => 'Normal',
      DiagnosticsLogLevel.debug => 'Verbose',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    return AleraSettingsGroup(
      title: 'Diagnostics',
      description:
          'Alera keeps rotating log files on this computer so an error can be '
          'reviewed after it happens.',
      children: <Widget>[
        SettingsButtonRow(
          title: 'Open Logs Folder',
          description: 'Show the folder holding the app log files.',
          buttonLabel: 'Open',
          onPressed: () => _openLogsFolder(context, ref),
        ),
        SettingsButtonRow(
          title: 'Export Diagnostics',
          description:
              'Save a zip with app and runtime logs plus version details. '
              'Secrets such as tokens are masked before anything is written.',
          buttonLabel: 'Export',
          onPressed: () => _exportBundle(context, ref),
        ),
        AleraSettingRow(
          title: 'Log Level',
          description: 'How much detail is written to the log files.',
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 200,
              child: AleraDropdownField<DiagnosticsLogLevel>(
                value: diagnostics.logLevel,
                entries: <AleraDropdownFieldEntry<DiagnosticsLogLevel>>[
                  for (final level in DiagnosticsLogLevel.values)
                    AleraDropdownFieldEntry<DiagnosticsLogLevel>(
                      value: level,
                      label: logLevelLabel(level),
                    ),
                ],
                onChanged: controller.setDiagnosticsLogLevel,
              ),
            ),
          ),
        ),
        SettingsSwitchRow(
          title: 'Send Crash Reports',
          description:
              'Send crashes to Sentry, an external service. Off by default; '
              'local log files work either way.',
          value: diagnostics.crashReportingEnabled,
          onChanged: controller.setCrashReportingEnabled,
        ),
      ],
    );
  }

  Future<void> _openLogsFolder(BuildContext context, WidgetRef ref) async {
    final opened = await ref
        .read(diagnosticsServiceProvider)
        .revealAppLogDirectory();
    if (!context.mounted || opened) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Could not open the logs folder.',
      tone: AleraToastTone.error,
    );
  }

  Future<void> _exportBundle(BuildContext context, WidgetRef ref) async {
    final service = ref.read(diagnosticsServiceProvider);
    // Read before the picker opens: awaiting a dialog first would leave the
    // most recent lines out of the bundle.
    final runtime = await ref.read(runtimeDiagnosticsInfoProvider.future);
    final bytes = await service.buildBundle(runtime: runtime);

    final location = await getSaveLocation(
      suggestedName: service.suggestedFileName(),
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Zip Archive', extensions: <String>['zip']),
      ],
    );
    if (location == null) {
      return;
    }
    await XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: 'application/zip',
    ).saveTo(location.path);

    if (!context.mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Diagnostics exported.',
      tone: AleraToastTone.success,
    );
  }
}
