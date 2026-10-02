part of 'ai_assist_pane.dart';

extension on _AiAssistSettingsPaneState {
  void _loadChatGptOptionsSupport() {
    if (_chatGptOptionsChecked || !_usesChatGpt(widget.settings)) {
      return;
    }
    _chatGptOptionsChecked = true;
    final client = ref.read(runtimeHostClientProvider);
    unawaited(() async {
      try {
        final supported = await client.supportsRuntimeCapability(
          aleraRuntimeHostAiAssistChatGptOptionsCapability,
        );
        if (!mounted) return;
        _updateChatGptOptionsSupported(supported);
      } catch (_) {
        if (mounted) {
          _chatGptOptionsChecked = false;
        }
      }
    }());
  }

  void _autoDiscoverConfiguredAgents() {
    if (!mounted || !widget.settings.enabled) {
      return;
    }
    final agents = aiAssistAgentsForModelDiscovery(
      widget.settings,
      _AiAssistSettingsPaneState._configuredOperations,
    );
    for (final agent in agents) {
      _autoDiscoverAgent(agent);
    }
  }

  void _autoDiscoverAgent(AiAssistAgent agent) {
    final spec = aiAssistAgentSpecs[agent];
    if (spec == null ||
        !spec.canDiscoverModels ||
        _autoDiscovered.contains(agent) ||
        (_discovery[agent]?.loading ?? false)) {
      return;
    }
    _autoDiscovered.add(agent);
    unawaited(_discoverModels(agent));
  }

  Future<void> _discoverModels(
    AiAssistAgent agent, {
    bool force = false,
  }) async {
    final spec = aiAssistAgentSpecs[agent];
    if (spec == null || !spec.canDiscoverModels) {
      return;
    }
    if (!force && (_discovery[agent]?.loading ?? false)) {
      return;
    }
    final generation = (_discoveryGeneration[agent] ?? 0) + 1;
    _discoveryGeneration[agent] = generation;
    _updateDiscoveryState(
      agent,
      const AiAssistModelDiscoveryState(loading: true),
    );
    final AiAssistModelDiscoveryResult result;
    try {
      result = await ref
          .read(aiAssistModelDiscoveryServiceProvider)
          .discover(agent);
    } catch (error) {
      if (!mounted || _discoveryGeneration[agent] != generation) {
        return;
      }
      _updateDiscoveryState(
        agent,
        AiAssistModelDiscoveryState(error: error.toString()),
      );
      _autoDiscovered.remove(agent);
      return;
    }
    if (!mounted || _discoveryGeneration[agent] != generation) {
      return;
    }
    if (!result.success) {
      _updateDiscoveryState(
        agent,
        AiAssistModelDiscoveryState(error: result.error),
      );
      _autoDiscovered.remove(agent);
      return;
    }
    widget.onChanged((latest) {
      final discoveredDefaults = <AiAssistAgent, String>{
        ...latest.discoveredDefaultModelByAgent,
      };
      if (result.defaultModelId == null) {
        discoveredDefaults.remove(agent);
      } else {
        discoveredDefaults[agent] = result.defaultModelId!;
      }
      return latest.copyWith(
        discoveredModelsByAgent: <AiAssistAgent, List<AiAssistDiscoveredModel>>{
          ...latest.discoveredModelsByAgent,
          agent: <AiAssistDiscoveredModel>[
            for (final model in result.models) model.toDiscovered(),
          ],
        },
        discoveredDefaultModelByAgent: discoveredDefaults,
      );
    });
    _updateDiscoveryState(agent, const AiAssistModelDiscoveryState());
  }
}
