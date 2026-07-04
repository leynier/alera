import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:alera/src/features/settings/presentation/panes/application_workspace_directory_row.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:alera/src/features/updater/presentation/update_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App-level preferences: storage, safety confirmations, updates, and the
/// support row.
class ApplicationSettingsPane extends ConsumerWidget {
  const ApplicationSettingsPane({
    super.key,
    required this.general,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final GeneralSettings general;
  final Map<String, GlobalKey> groupKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starState = ref.watch(gitHubStarControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: groupKeys['storage'],
          child: AleraPanel(
            children: <Widget>[
              WorkspaceDirectoryRow(
                value: general.workspaceDirectory,
                onChanged: (next) => ref
                    .read(settingsControllerProvider.notifier)
                    .updateWorkspaceDirectory(next),
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
                onChanged: (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .setConfirmProjectRemoval(value),
              ),
              SettingsSwitchRow(
                title: 'Confirm Workspace Removal',
                description:
                    'Ask before removing a linked workspace and deleting its branch.',
                value: general.confirmWorkspaceRemoval,
                onChanged: (value) => ref
                    .read(settingsControllerProvider.notifier)
                    .setConfirmWorkspaceRemoval(value),
              ),
            ],
          ),
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
