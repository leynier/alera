part of 'agent_profiles_pane.dart';

extension _AgentProfilesPaneDiscovery on _AgentProfilesSettingsPaneState {
  List<ManagedAgentOption> _modelsFor(AgentType adapter) {
    final discovered = _discoveredModels[adapter];
    if (discovered != null) {
      return discovered;
    }
    final spec = aiAssistAgentSpecs[_aiAssistAgent(adapter)];
    return <ManagedAgentOption>[
      for (final model in spec?.models ?? const <AiAssistModel>[])
        ManagedAgentOption(model.id, model.label),
    ];
  }

  List<ManagedAgentOption> _personasFor(AgentType adapter) {
    final discovered = _discoveredPersonas[adapter];
    if (discovered != null) {
      return discovered;
    }
    return switch (adapter) {
      AgentType.opencode || AgentType.opencode2 => const <ManagedAgentOption>[
        ManagedAgentOption('build', 'Build'),
      ],
      _ => const <ManagedAgentOption>[],
    };
  }

  bool _canDiscoverModels(AgentType adapter) {
    return aiAssistAgentSpecs[_aiAssistAgent(adapter)]?.modelsCommand != null;
  }

  bool _canDiscoverPersonas(AgentType adapter) {
    return adapter == AgentType.agy ||
        adapter == AgentType.opencode ||
        adapter == AgentType.opencode2;
  }

  void _scheduleDiscovery(AgentType adapter) {
    if (!_autoDiscoveryScheduled.add(adapter)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_canDiscoverModels(adapter)) {
        unawaited(_discoverModels(adapter));
      }
      if (_canDiscoverPersonas(adapter)) {
        unawaited(_discoverPersonas(adapter));
      }
    });
  }

  Future<void> _discoverModels(AgentType adapter) async {
    final agent = _aiAssistAgent(adapter);
    if (agent == null || !_loadingModels.add(adapter)) {
      return;
    }
    _setDiscoveryState(() {
      _discoveryErrors.remove(adapter);
    });
    try {
      final result = await ref
          .read(aiAssistModelDiscoveryServiceProvider)
          .discover(agent);
      if (!mounted) {
        return;
      }
      _setDiscoveryState(() {
        if (result.success) {
          _discoveredModels[adapter] = <ManagedAgentOption>[
            for (final model in result.models)
              ManagedAgentOption(model.id, model.label),
          ];
        } else if (result.error != null) {
          _discoveryErrors[adapter] = result.error!;
        }
      });
    } catch (error) {
      if (mounted) {
        _setDiscoveryState(() => _discoveryErrors[adapter] = error.toString());
      }
    } finally {
      if (mounted) {
        _setDiscoveryState(() => _loadingModels.remove(adapter));
      } else {
        _loadingModels.remove(adapter);
      }
    }
  }

  Future<void> _discoverPersonas(AgentType adapter) async {
    if (!_loadingPersonas.add(adapter)) {
      return;
    }
    _setDiscoveryState(() {
      _discoveryErrors.remove(adapter);
    });
    try {
      final result = await ref
          .read(agentProfilePersonaDiscoveryProvider)
          .discover(adapter);
      if (!mounted) {
        return;
      }
      _setDiscoveryState(() {
        _discoveredPersonas[adapter] = <ManagedAgentOption>[
          for (final persona in result.personas)
            ManagedAgentOption(persona, _titleFromId(persona)),
        ];
        if (result.error != null) {
          _discoveryErrors[adapter] = result.error!;
        }
      });
    } catch (error) {
      if (mounted) {
        _setDiscoveryState(() => _discoveryErrors[adapter] = error.toString());
      }
    } finally {
      if (mounted) {
        _setDiscoveryState(() => _loadingPersonas.remove(adapter));
      } else {
        _loadingPersonas.remove(adapter);
      }
    }
  }
}

AiAssistAgent? _aiAssistAgent(AgentType adapter) {
  for (final agent in AiAssistAgent.values) {
    if (agent.agentType == adapter) {
      return agent;
    }
  }
  return null;
}

String _titleFromId(String value) {
  return value
      .split(RegExp(r'[-_.\s]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}
