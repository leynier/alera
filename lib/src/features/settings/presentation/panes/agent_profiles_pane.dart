import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                          onTap: () => _selectProfile(profile),
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
            hasSelection: _selectedProfileId != null,
            saving: _saving,
            error: _error,
            onAdapterChanged: _selectAdapter,
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
  }

  void _clearEditor() {
    _seededSignature = null;
    _selectedProfileId = null;
    _nameController.clear();
    _descriptionController.clear();
    _quotaGroupController.clear();
    _adapter = AgentType.codex;
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
    });
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (command.isEmpty) {
      setState(() => _error = 'Command is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final quotaGroup = _quotaGroupController.text.trim();
      final saved = await ref
          .read(agentProfileRepositoryProvider)
          .upsert(
            id: _selectedProfileId,
            name: name,
            agentType: _adapter.key,
            command: command,
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
      await ref.read(agentProfileRepositoryProvider).remove(profile.id);
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
}
