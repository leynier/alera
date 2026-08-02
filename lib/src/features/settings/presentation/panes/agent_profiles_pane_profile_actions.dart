part of 'agent_profiles_pane.dart';

extension _AgentProfilesPaneProfileActions on _AgentProfilesSettingsPaneState {
  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    if (name.isEmpty) {
      _setPaneState(() => _error = 'Name is required.');
      return;
    }
    if (_launchMode == AgentProfileLaunchMode.command && command.isEmpty) {
      _setPaneState(() => _error = 'Command is required.');
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
    _setPaneState(() {
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
            customPrompt: _customPromptController.text.trim(),
            description: _descriptionController.text.trim(),
            quotaGroup: quotaGroup.isEmpty ? null : quotaGroup,
          );
      if (!mounted) {
        return;
      }
      _setPaneState(() {
        _saving = false;
        _creatingNew = false;
        _selectedProfileId = saved.id;
        _seededSignature = null;
      });
      AleraToast.show(
        context,
        message: 'Agent profile saved',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setPaneState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _testCommand() async {
    final command =
        (_launchMode == AgentProfileLaunchMode.managed
                ? managedAgentCommandPreview(_adapter, _managedConfig)
                : _commandController.text)
            .trim();
    if (command.isEmpty) {
      _setPaneState(() => _error = 'Command is required.');
      return;
    }
    await showCommandTerminalDialog(
      context,
      ref,
      CommandTerminalRequest(
        title: 'Test Agent Profile',
        command: command,
        description:
            'The profile command runs here. It does not receive a dispatched task.',
      ),
    );
  }

  Future<void> _removeProfile(AgentProfile profile) async {
    _setPaneState(() {
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
      _setPaneState(() {
        _saving = false;
        _creatingNew = false;
        _clearEditor();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setPaneState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _setDefaultProfile(AgentProfile profile) async {
    _setPaneState(() {
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
      _setPaneState(() => _saving = false);
      AleraToast.show(
        context,
        message: 'Default agent profile updated',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (mounted) {
        _setPaneState(() {
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
    _setPaneState(() {
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
      _setPaneState(() {
        _saving = false;
        _creatingNew = false;
        _selectedProfileId = cloned.id;
        _seededSignature = null;
      });
      AleraToast.show(
        context,
        message: 'Agent profile cloned',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _setPaneState(() {
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
    _setPaneState(() {
      _managedConfig = sanitized;
      _error = null;
    });
  }
}
