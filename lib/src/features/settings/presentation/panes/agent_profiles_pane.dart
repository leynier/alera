import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_providers.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/automations/presentation/automation_policy_sections.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_profiles_pane_discovery.dart';
part 'agent_profiles_pane_profile_actions.dart';

class AgentProfilesSettingsPane extends ConsumerStatefulWidget {
  const AgentProfilesSettingsPane({super.key});

  @override
  ConsumerState<AgentProfilesSettingsPane> createState() =>
      _AgentProfilesSettingsPaneState();
}

class _AgentProfilesSettingsPaneState
    extends ConsumerState<AgentProfilesSettingsPane> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _customPromptController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _quotaGroupController = TextEditingController();
  String? _selectedProfileId;
  int? _selectedProfileRevision;
  bool _creatingNew = false;
  AgentType _adapter = AgentType.codex;
  AgentProfileLaunchMode _launchMode = AgentProfileLaunchMode.managed;
  Map<String, Object?> _managedConfig = <String, Object?>{};
  AgentType _originalAdapter = AgentType.codex;
  AgentProfileLaunchMode _originalLaunchMode = AgentProfileLaunchMode.managed;
  Map<String, Object?> _originalManagedConfig = <String, Object?>{};
  final Map<AgentType, List<ManagedAgentOption>> _discoveredModels =
      <AgentType, List<ManagedAgentOption>>{};
  final Map<AgentType, List<ManagedAgentOption>> _discoveredPersonas =
      <AgentType, List<ManagedAgentOption>>{};
  final Map<AgentType, String> _discoveryErrors = <AgentType, String>{};
  final Set<AgentType> _loadingModels = <AgentType>{};
  final Set<AgentType> _loadingPersonas = <AgentType>{};
  final Set<AgentType> _autoDiscoveryScheduled = <AgentType>{};
  String? _error;
  bool _saving = false;
  String? _seededSignature;

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _customPromptController.dispose();
    _descriptionController.dispose();
    _quotaGroupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(agentProfilesProvider);
    final defaultAgentProfileId = ref
        .watch(settingsControllerProvider)
        .agents
        .defaultAgentProfileId;
    return profilesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AleraEmptyState(
        icon: AleraIcons.agent,
        title: 'Agent profiles unavailable',
        message: error.toString(),
      ),
      data: (profiles) {
        var selected = _selectedProfile(profiles);
        if (selected != null) {
          _seedFromProfile(selected);
        } else if (!_creatingNew) {
          if (profiles.isNotEmpty) {
            selected = profiles.first;
            _selectedProfileId = selected.id;
            _seedFromProfile(selected);
          } else if (_selectedProfileId != null) {
            _clearEditor();
          }
        }
        final selectedProfile = selected;
        return AleraMasterDetail(
          masterTitle: 'Agent Profiles',
          masterAction: AleraIconButton(
            tooltip: 'New Profile',
            icon: AleraIcons.add,
            onPressed: _newProfile,
          ),
          master: profiles.isEmpty
              ? const AleraEmptyState(
                  icon: AleraIcons.agent,
                  title: 'No agent profiles',
                  message:
                      'Declare a profile to let a run dispatch work to it.',
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: AleraTokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                    border: Border.all(color: AleraTokens.borderSubtle),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: profiles.length,
                      onReorderItem: (oldIndex, newIndex) => unawaited(
                        _reorderProfiles(profiles, oldIndex, newIndex),
                      ),
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        return AgentProfileListRow(
                          key: ValueKey<String>(profile.id),
                          profile: profile,
                          selected: profile.id == _selectedProfileId,
                          isDefault: profile.id == defaultAgentProfileId,
                          onTap: () => _selectProfile(profile),
                          onSetDefault:
                              _saving || profile.id == defaultAgentProfileId
                              ? null
                              : () => unawaited(_setDefaultProfile(profile)),
                          onClone: _saving
                              ? null
                              : () =>
                                    unawaited(_cloneProfile(profile, profiles)),
                          dragHandle: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(
                              AleraIcons.dragHandle,
                              size: 16,
                              color: AleraTokens.foregroundFaint,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
          detail: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AgentProfileEditor(
                  nameController: _nameController,
                  commandController: _commandController,
                  customPromptController: _customPromptController,
                  descriptionController: _descriptionController,
                  quotaGroupController: _quotaGroupController,
                  adapter: _adapter,
                  launchMode: _launchMode,
                  managedConfig: _managedConfig,
                  models: _modelsFor(_adapter),
                  personas: _personasFor(_adapter),
                  hasSelection: _selectedProfileId != null,
                  saving: _saving,
                  modelsLoading: _loadingModels.contains(_adapter),
                  personasLoading: _loadingPersonas.contains(_adapter),
                  discoveryError: _discoveryErrors[_adapter],
                  error: _error,
                  onAdapterChanged: _selectAdapter,
                  onLaunchModeChanged: (value) {
                    setState(() {
                      _launchMode = value;
                      _error = null;
                    });
                    if (value == AgentProfileLaunchMode.managed) {
                      _scheduleDiscovery(_adapter);
                    }
                  },
                  onManagedConfigChanged: _updateManagedConfig,
                  onRefreshModels: _canDiscoverModels(_adapter)
                      ? () => unawaited(_discoverModels(_adapter))
                      : null,
                  onRefreshPersonas: _canDiscoverPersonas(_adapter)
                      ? () => unawaited(_discoverPersonas(_adapter))
                      : null,
                  onSave: _saveProfile,
                  onRemove: selectedProfile == null
                      ? null
                      : () => _removeProfile(selectedProfile),
                  onTestCommand: () => unawaited(_testCommand()),
                ),
                if (selectedProfile != null) ...<Widget>[
                  const SizedBox(height: AleraTokens.space16),
                  AutomationProfilePolicySection(profileId: selectedProfile.id),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  AgentProfile? _selectedProfile(List<AgentProfile> profiles) {
    final selectedId = _selectedProfileId;
    if (selectedId == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == selectedId) {
        return profile;
      }
    }
    return null;
  }

  /// Reseeds the form only when the underlying profile actually changed, so a
  /// rebuild triggered by an unrelated runtime event does not discard edits in
  /// progress.
  void _seedFromProfile(AgentProfile profile) {
    _selectedProfileRevision = profile.revision;
    final signature = <String>[
      profile.id,
      profile.name,
      profile.agentType,
      profile.command,
      profile.launchMode.name,
      jsonEncode(profile.managedConfig),
      profile.customPrompt,
      profile.description,
      profile.quotaGroup ?? '',
    ].join('|');
    if (_seededSignature == signature) {
      return;
    }
    _seededSignature = signature;
    _nameController.text = profile.name;
    _commandController.text = profile.command;
    _customPromptController.text = profile.customPrompt;
    _descriptionController.text = profile.description;
    _quotaGroupController.text = profile.quotaGroup ?? '';
    _adapter = agentProfileAdapterFromKey(profile.agentType) ?? AgentType.codex;
    _launchMode = profile.launchMode;
    _managedConfig = <String, Object?>{...profile.managedConfig};
    _originalAdapter = _adapter;
    _originalLaunchMode = _launchMode;
    _originalManagedConfig = <String, Object?>{...profile.managedConfig};
    if (_launchMode == AgentProfileLaunchMode.managed) {
      _scheduleDiscovery(_adapter);
    }
  }

  void _clearEditor() {
    _seededSignature = null;
    _selectedProfileId = null;
    _selectedProfileRevision = null;
    _nameController.clear();
    _customPromptController.clear();
    _descriptionController.clear();
    _quotaGroupController.clear();
    _adapter = AgentType.codex;
    _launchMode = AgentProfileLaunchMode.managed;
    _managedConfig = <String, Object?>{};
    _originalAdapter = AgentType.codex;
    _originalLaunchMode = AgentProfileLaunchMode.managed;
    _originalManagedConfig = <String, Object?>{};
    _commandController.text = agentProfileDefaultCommands[_adapter] ?? '';
  }

  void _selectProfile(AgentProfile profile) {
    setState(() {
      _creatingNew = false;
      _error = null;
      _selectedProfileId = profile.id;
      _seededSignature = null;
    });
  }

  void _newProfile() {
    setState(() {
      _creatingNew = true;
      _error = null;
      _clearEditor();
    });
    _scheduleDiscovery(_adapter);
  }

  void _selectAdapter(AgentType adapter) {
    setState(() {
      // Swapping the adapter reseeds the command only while it still holds
      // another adapter's default, so a command the user typed survives.
      final defaults = agentProfileDefaultCommands.values.toSet();
      if (defaults.contains(_commandController.text.trim())) {
        _commandController.text = agentProfileDefaultCommands[adapter] ?? '';
      }
      _adapter = adapter;
      _managedConfig = <String, Object?>{};
      _error = null;
    });
    if (_launchMode == AgentProfileLaunchMode.managed) {
      _scheduleDiscovery(adapter);
    }
  }

  void _setDiscoveryState(VoidCallback update) {
    setState(update);
  }

  void _setPaneState(VoidCallback update) {
    setState(update);
  }
}
