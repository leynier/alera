import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/application_diagnostics_section.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:alera/src/features/settings/presentation/panes/application_workspace_directory_row.dart';
import 'package:alera/src/features/automations/presentation/automation_settings_section.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-level preferences: storage, safety confirmations, runtime lifecycle,
/// updates, and the support row.
class ApplicationSettingsPane extends ConsumerWidget {
  const ApplicationSettingsPane({
    super.key,
    required this.general,
    required this.terminal,
    required this.diagnostics,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final GeneralSettings general;
  final TerminalSettings terminal;
  final DiagnosticsSettings diagnostics;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starState = ref.watch(gitHubStarControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['storage'],
          child: AleraPanel(
            children: <Widget>[
              WorkspaceDirectoryRow(
                value: general.workspaceDirectory,
                onChanged: (next) => controller.updateWorkspaceDirectory(next),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['safety'],
          child: AleraSettingsGroup(
            title: 'Safety',
            description:
                'Confirmation prompts for destructive workspace actions.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Confirm Project Removal',
                description:
                    'Ask before unregistering a project and deleting its workspace metadata.',
                value: general.confirmProjectRemoval,
                onChanged: (value) =>
                    controller.setConfirmProjectRemoval(value),
              ),
              SettingsSwitchRow(
                title: 'Confirm Workspace Removal',
                description:
                    'Ask before removing a linked workspace and deleting its branch.',
                value: general.confirmWorkspaceRemoval,
                onChanged: (value) =>
                    controller.setConfirmWorkspaceRemoval(value),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: groupKeys['runtime'],
          child: AleraSettingsGroup(
            title: 'Runtime',
            description:
                'Lifecycle of the local runtime host that owns terminal sessions.',
            children: <Widget>[
              SettingsSwitchRow(
                title: 'Keep Runtime Open When App Quits',
                description:
                    'Leave the app-launched sidecar running after a clean quit. Persistent CLI runtimes are never stopped by quitting, and unexpected exits always leave the host up.',
                value: terminal.keepRuntimeOpenOnAppQuit,
                onChanged: (value) => controller.updateTerminal(
                  terminal.copyWith(keepRuntimeOpenOnAppQuit: value),
                ),
              ),
              SettingsIntegerRow(
                title: 'Empty Host Shutdown',
                description:
                    'Seconds to keep the host alive after the app closes with no running sessions.',
                value: terminal.hostEmptyShutdownDelaySeconds,
                min: 5,
                max: 3600,
                step: 5,
                suffix: 's',
                onChanged: (value) => controller.updateTerminal(
                  terminal.copyWith(hostEmptyShutdownDelaySeconds: value),
                ),
              ),
              SettingsIntegerRow(
                title: 'Detached Session Shutdown',
                description:
                    'Seconds to keep detached running sessions alive after the app closes.',
                value: terminal.hostDetachedSessionShutdownDelaySeconds,
                min: 5,
                max: 86400,
                step: 60,
                suffix: 's',
                onChanged: (value) => controller.updateTerminal(
                  terminal.copyWith(
                    hostDetachedSessionShutdownDelaySeconds: value,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space24),
        KeyedSubtree(
          key: groupKeys['automations'],
          child: const AutomationSettingsSection(),
        ),
        const SizedBox(height: AleraTokens.space24),
        KeyedSubtree(
          key: groupKeys['diagnostics'],
          child: DiagnosticsSettingsSection(diagnostics: diagnostics),
        ),
        const SizedBox(height: AleraTokens.space24),
        KeyedSubtree(
          key: groupKeys['updates'],
          child: const UpdateSettingsSection(),
        ),
        if (starState != GitHubStarState.hidden) ...<Widget>[
          const SizedBox(height: AleraTokens.space24),
          KeyedSubtree(
            key: groupKeys['support'],
            child: SupportAleraSection(state: starState),
          ),
        ],
      ],
    );
  }
}
