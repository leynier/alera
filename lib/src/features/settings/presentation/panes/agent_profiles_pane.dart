import 'dart:async';
import 'dart:convert';

import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_providers.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_profiles_pane_discovery.dart';

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
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _quotaGroupController = TextEditingController();
  String? _selectedProfileId;
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
        title: 'Agent Profiles Unavailable',
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
                  title: 'No Agent Profiles',
                  message:
                      'Declare A Profile To Let A Run Dispatch Work To It.',
                )
              : SingleChildScrollView(
                  child: AleraPanel(
                    clipBehavior: Clip.antiAlias,
                    children: <Widget>[
                      for (final profile in profiles)
                        AgentProfileListRow(
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
                        ),
                    ],
                  ),
                ),
          detail: AgentProfileEditor(
            nameController: _nameController,
            commandController: _commandController,
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
    final signature = <String>[
      profile.id,
      profile.name,
      profile.agentType,
      profile.command,
      profile.launchMode.name,
      jsonEncode(profile.managedConfig),
      profile.description,
      profile.quotaGroup ?? '',
    ].join('|');
    if (_seededSignature == signature) {
      return;
    }
    _seededSignature = signature;
    _nameController.text = profile.name;
    _commandController.text = profile.command;
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
    _nameController.clear();
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

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_launchMode == AgentProfileLaunchMode.command && command.isEmpty) {
      setState(() => _error = 'Command is required.');
      return;
    }
    final nextRisks = managedAgentRiskMarkers(_adapter, _managedConfig);
    final originalRisks =
        _originalLaunchMode == AgentProfileLaunchMode.managed &&
            _originalAdapter == _adapter
        ? managedAgentRiskMarkers(_originalAdapter, _originalManagedConfig)
        : const <String>{};
    if (_launchMode == AgentProfileLaunchMode.managed &&
        nextRisks.difference(originalRisks).isNotEmpty) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (_) => AleraConfirmDialog(
              title: 'Confirm Reduced Protections',
              message: managedAgentRiskWarning(_adapter, _managedConfig),
              confirmLabel: 'Save Anyway',
              destructive: true,
            ),
          ) ??
          false;
      if (!confirmed || !mounted) {
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quotaGroup = _quotaGroupController.text.trim();
      final saved = await ref
          .read(agentProfilesProvider.notifier)
          .upsert(
            id: _selectedProfileId,
            name: name,
            agentType: _adapter.key,
            launchMode: _launchMode,
            command: command,
            managedConfig: _managedConfig,
            description: _descriptionController.text.trim(),
            quotaGroup: quotaGroup.isEmpty ? null : quotaGroup,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _creatingNew = false;
        _selectedProfileId = saved.id;
        _seededSignature = null;
      });
      AleraToast.show(
        context,
        message: 'Agent Profile Saved',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _removeProfile(AgentProfile profile) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(agentProfilesProvider.notifier).remove(profile.id);
      if (ref.read(settingsControllerProvider).agents.defaultAgentProfileId ==
          profile.id) {
        await ref
            .read(settingsControllerProvider.notifier)
            .setDefaultAgentProfile(null);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _creatingNew = false;
        _clearEditor();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _setDefaultProfile(AgentProfile profile) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setDefaultAgentProfile(profile.id);
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      AleraToast.show(
        context,
        message: 'Default Agent Profile Updated',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _cloneProfile(
    AgentProfile source,
    List<AgentProfile> profiles,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cloned = await ref
          .read(agentProfilesProvider.notifier)
          .clone(source, name: _cloneName(source, profiles));
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _creatingNew = false;
        _selectedProfileId = cloned.id;
        _seededSignature = null;
      });
      AleraToast.show(
        context,
        message: 'Agent Profile Cloned',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  String _cloneName(AgentProfile source, List<AgentProfile> profiles) {
    final base = '${source.name.trim()} Copy';
    final names = <String>{
      for (final profile in profiles) profile.name.trim().toLowerCase(),
    };
    if (!names.contains(base.toLowerCase())) {
      return base;
    }
    for (var suffix = 2; ; suffix++) {
      final candidate = '$base $suffix';
      if (!names.contains(candidate.toLowerCase())) {
        return candidate;
      }
    }
  }

  void _updateManagedConfig(Map<String, Object?> next) {
    final sanitized = <String, Object?>{...next};
    if (_adapter == AgentType.codex) {
      final bypassWasEnabled =
          _managedConfig['bypassApprovalsAndSandbox'] == true;
      final sandboxChanged =
          sanitized['sandbox'] != _managedConfig['sandbox'] ||
          sanitized['approvalPolicy'] != _managedConfig['approvalPolicy'];
      if (sanitized['bypassApprovalsAndSandbox'] == true && !bypassWasEnabled) {
        sanitized
          ..remove('sandbox')
          ..remove('approvalPolicy');
      } else if (bypassWasEnabled && sandboxChanged) {
        sanitized.remove('bypassApprovalsAndSandbox');
      }
    }
    setState(() {
      _managedConfig = sanitized;
      _error = null;
    });
  }

  void _setDiscoveryState(VoidCallback update) {
    setState(update);
  }
}
