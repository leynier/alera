part of 'settings_dialog.dart';

class _AiTextSettingsPane extends ConsumerStatefulWidget {
  const _AiTextSettingsPane({required this.settings, required this.onChanged});

  final AiTextGenerationSettings settings;
  final ValueChanged<AiTextGenerationSettings> onChanged;

  @override
  ConsumerState<_AiTextSettingsPane> createState() =>
      _AiTextSettingsPaneState();
}

class _AiTextSettingsPaneState extends ConsumerState<_AiTextSettingsPane> {
  final Map<AiTextGenerationAgent, _AiTextModelDiscoveryState> _discovery =
      <AiTextGenerationAgent, _AiTextModelDiscoveryState>{};
  final Set<AiTextGenerationAgent> _autoDiscovered = <AiTextGenerationAgent>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDiscoverActiveAgent();
    });
  }

  @override
  void didUpdateWidget(covariant _AiTextSettingsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.agent != widget.settings.agent ||
        oldWidget.settings.enabled != widget.settings.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoDiscoverActiveAgent();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final agent = settings.agent;
    final spec = aiTextAgentSpecs[agent];
    final models = modelsForAgent(agent, settings);
    final model = modelForAgent(
      agent,
      settings.modelFor(agent) ?? defaultModelIdForAgent(agent, settings),
      extraModels: discoveredModelsForAgent(settings, agent),
    );
    final thinkingLevels = model.thinkingLevels;
    final discovery = _discovery[agent] ?? const _AiTextModelDiscoveryState();
    final canDiscoverModels = spec?.modelsCommand != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsGroup(
          title: 'Generation',
          description:
              'Local agent CLIs generate text from source control context.',
          children: <Widget>[
            _SwitchSettingRow(
              title: 'Enable AI text',
              description: 'Show generation actions in source control.',
              value: widget.settings.enabled,
              onChanged: (value) =>
                  widget.onChanged(settings.copyWith(enabled: value)),
            ),
            _AiTextAgentRow(
              value: agent,
              onChanged: (value) =>
                  widget.onChanged(settings.copyWith(agent: value)),
            ),
            if (agent == AiTextGenerationAgent.custom)
              _TextSettingRow(
                title: 'Custom command',
                description:
                    'Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.',
                value: settings.customCommand,
                hintText: 'llm --system commit-message',
                onChanged: (value) =>
                    widget.onChanged(settings.copyWith(customCommand: value)),
              )
            else if (spec != null)
              _AiTextModelRow(
                agent: agent,
                models: models,
                value: model.id,
                canDiscoverModels: canDiscoverModels,
                discovering: discovery.loading,
                discoveryError: discovery.error,
                onRefreshModels: canDiscoverModels
                    ? () => unawaited(_discoverModels(agent))
                    : null,
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    selectedModelByAgent: <AiTextGenerationAgent, String>{
                      ...settings.selectedModelByAgent,
                      agent: value,
                    },
                  ),
                ),
              ),
            if (thinkingLevels.isNotEmpty)
              _AiTextThinkingRow(
                levels: thinkingLevels,
                value:
                    settings.thinkingForModel(model.id) ??
                    model.defaultThinkingLevel ??
                    thinkingLevels.first.id,
                onChanged: (value) => widget.onChanged(
                  settings.copyWith(
                    selectedThinkingByModel: <String, String>{
                      ...settings.selectedThinkingByModel,
                      model.id: value,
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Instructions',
          description: 'Extra guidance appended to commit-message prompts.',
          children: <Widget>[
            _InstructionSettingRow(
              title: AiTextGenerationOperation.commitMessage.label,
              value: settings.instructionsFor(
                AiTextGenerationOperation.commitMessage,
              ),
              onChanged: (value) => widget.onChanged(
                settings.copyWith(
                  instructionsByOperation: <AiTextGenerationOperation, String>{
                    ...settings.instructionsByOperation,
                    AiTextGenerationOperation.commitMessage: value,
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _autoDiscoverActiveAgent() {
    if (!mounted || !widget.settings.enabled) {
      return;
    }
    final agent = widget.settings.agent;
    final spec = aiTextAgentSpecs[agent];
    if (spec?.modelsCommand == null ||
        _autoDiscovered.contains(agent) ||
        (_discovery[agent]?.loading ?? false)) {
      return;
    }
    _autoDiscovered.add(agent);
    unawaited(_discoverModels(agent));
  }

  Future<void> _discoverModels(AiTextGenerationAgent agent) async {
    final spec = aiTextAgentSpecs[agent];
    if (spec?.modelsCommand == null) {
      return;
    }
    setState(() {
      _discovery[agent] = const _AiTextModelDiscoveryState(loading: true);
    });
    final AiTextModelDiscoveryResult result;
    try {
      result = await ref
          .read(aiTextModelDiscoveryServiceProvider)
          .discover(agent);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _discovery[agent] = _AiTextModelDiscoveryState(error: error.toString());
      });
      return;
    }
    if (!mounted) {
      return;
    }
    if (!result.success) {
      setState(() {
        _discovery[agent] = _AiTextModelDiscoveryState(error: result.error);
      });
      return;
    }
    final latest = widget.settings;
    widget.onChanged(
      latest.copyWith(
        discoveredModelsByAgent:
            <AiTextGenerationAgent, List<AiTextDiscoveredModel>>{
              ...latest.discoveredModelsByAgent,
              agent: <AiTextDiscoveredModel>[
                for (final model in result.models) model.toDiscovered(),
              ],
            },
        discoveredDefaultModelByAgent: <AiTextGenerationAgent, String>{
          ...latest.discoveredDefaultModelByAgent,
          agent: result.defaultModelId,
        },
      ),
    );
    setState(() {
      _discovery[agent] = const _AiTextModelDiscoveryState();
    });
  }
}

class _AiTextModelDiscoveryState {
  const _AiTextModelDiscoveryState({this.loading = false, this.error});

  final bool loading;
  final String? error;
}

class _AiTextAgentRow extends StatelessWidget {
  const _AiTextAgentRow({required this.value, required this.onChanged});

  final AiTextGenerationAgent value;
  final ValueChanged<AiTextGenerationAgent> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: 'Agent',
      description: 'CLI used for generated source control text.',
      child: _AiTextSelectField<AiTextGenerationAgent>(
        key: ValueKey<String>('ai-text-agent-${value.key}'),
        value: value,
        label: value.label,
        entries: <_AiTextSelectEntry<AiTextGenerationAgent>>[
          for (final agent in AiTextGenerationAgent.values)
            _AiTextSelectEntry<AiTextGenerationAgent>(
              value: agent,
              label: agent.label,
            ),
        ],
        onChanged: (next) {
          onChanged(next);
        },
      ),
    );
  }
}

class _AiTextModelRow extends StatelessWidget {
  const _AiTextModelRow({
    required this.agent,
    required this.models,
    required this.value,
    required this.canDiscoverModels,
    required this.discovering,
    required this.discoveryError,
    required this.onRefreshModels,
    required this.onChanged,
  });

  final AiTextGenerationAgent agent;
  final List<AiTextModel> models;
  final String value;
  final bool canDiscoverModels;
  final bool discovering;
  final String? discoveryError;
  final VoidCallback? onRefreshModels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final known = models.any((model) => model.id == value);
    if (!known) {
      return _TextSettingRow(
        title: 'Model',
        description: 'Model passed to ${agent.label}.',
        value: value,
        onChanged: onChanged,
      );
    }
    return AleraSettingRow(
      title: 'Model',
      description: discoveryError == null
          ? 'Model passed to ${agent.label}.'
          : discoveryError!,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _AiTextSelectField<String>(
              key: ValueKey<String>('ai-text-model-${agent.key}-$value'),
              value: value,
              label: models.firstWhere((model) => model.id == value).label,
              entries: <_AiTextSelectEntry<String>>[
                for (final model in models)
                  _AiTextSelectEntry<String>(
                    value: model.id,
                    label: model.label,
                  ),
              ],
              onChanged: (next) {
                onChanged(next);
              },
            ),
          ),
          if (canDiscoverModels) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Refresh models',
              icon: discovering ? AleraIcons.sync : AleraIcons.refresh,
              onPressed: discovering ? null : onRefreshModels,
            ),
          ],
        ],
      ),
    );
  }
}

class _AiTextThinkingRow extends StatelessWidget {
  const _AiTextThinkingRow({
    required this.levels,
    required this.value,
    required this.onChanged,
  });

  final List<AiThinkingLevel> levels;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = levels.any((level) => level.id == value)
        ? value
        : levels.first.id;
    return AleraSettingRow(
      title: 'Thinking',
      description: 'Reasoning effort for models that support it.',
      child: _AiTextSelectField<String>(
        key: ValueKey<String>('ai-text-thinking-$value'),
        value: selected,
        label: levels.firstWhere((level) => level.id == selected).label,
        entries: <_AiTextSelectEntry<String>>[
          for (final level in levels)
            _AiTextSelectEntry<String>(value: level.id, label: level.label),
        ],
        onChanged: (next) {
          onChanged(next);
        },
      ),
    );
  }
}

class _AiTextSelectEntry<T> {
  const _AiTextSelectEntry({required this.value, required this.label});

  final T value;
  final String label;
}

class _AiTextSelectField<T> extends StatelessWidget {
  const _AiTextSelectField({
    super.key,
    required this.value,
    required this.label,
    required this.entries,
    required this.onChanged,
  });

  final T value;
  final String label;
  final List<_AiTextSelectEntry<T>> entries;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: () => unawaited(_openMenu(buttonContext)),
            child: InputDecorator(
              isEmpty: false,
              isFocused: false,
              decoration: const InputDecoration(
                isDense: true,
                suffixIcon: Icon(AleraIcons.chevronDown, size: 18),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (renderBox == null || overlay is! RenderBox) {
      return;
    }
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<T>>[
        for (final entry in entries)
          AleraDropdownEntry<T>(
            value: entry.value,
            label: entry.label,
            selected: entry.value == value,
          ),
      ],
    );
    if (selected != null && selected != value) {
      onChanged(selected);
    }
  }
}

class _InstructionSettingRow extends StatefulWidget {
  const _InstructionSettingRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_InstructionSettingRow> createState() => _InstructionSettingRowState();
}

class _InstructionSettingRowState extends State<_InstructionSettingRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(_InstructionSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value != widget.value) {
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: widget.title,
      description: 'Optional prompt guidance.',
      controlWidth: 360,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        minLines: 2,
        maxLines: 4,
        onEditingComplete: _commit,
        onSubmitted: (_) => _commit(),
        decoration: const InputDecoration(hintText: 'Optional instructions'),
      ),
    );
  }
}
