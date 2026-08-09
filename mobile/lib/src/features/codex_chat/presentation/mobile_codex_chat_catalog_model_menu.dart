part of 'mobile_codex_chat_screen.dart';

class _MobileModelMenuButton extends StatelessWidget {
  const _MobileModelMenuButton({
    required this.state,
    required this.onModel,
    required this.onReasoning,
    required this.onSpeed,
    required this.onCollaboration,
  });

  final MobileCodexState state;
  final ValueChanged<String?> onModel;
  final ValueChanged<String> onReasoning;
  final ValueChanged<String> onSpeed;
  final ValueChanged<String?> onCollaboration;

  @override
  Widget build(BuildContext context) {
    final model = state.models
        .where((item) => item.id == state.selectedModel)
        .firstOrNull;
    return TextButton.icon(
      onPressed: () => _show(context, model),
      icon: state.speedMode == 'fast'
          ? const Icon(Icons.bolt, size: AleraTokens.space12)
          : const SizedBox.shrink(),
      label: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: _mobileModelLabel(
                model?.label ?? state.selectedModel ?? 'Model',
              ),
              style: const TextStyle(color: AleraTokens.foreground),
            ),
            TextSpan(
              text: ' ${_mobileLabel(state.reasoningEffort)}',
              style: const TextStyle(color: AleraTokens.foregroundMuted),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _show(BuildContext context, MobileCodexModelOption? selected) {
    var selectedModel = selected;
    var selectedEffort = state.reasoningEffort;
    var selectedSpeed = state.speedMode;
    var selectedCollaboration = state.collaborationMode;
    final collaborationModes = <String>[
      for (final mode in state.collaborationModes)
        if (mode['mode']?.toString().trim() case final String value
            when value.isNotEmpty && value != 'plan')
          value,
    ];
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const ListTile(title: Text('Model')),
              for (final model in state.models)
                ListTile(
                  minTileHeight: AleraTokens.minTapTarget,
                  title: Text(_mobileModelLabel(model.label)),
                  trailing: model.id == selectedModel?.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setModalState(() {
                      selectedModel = model;
                      selectedEffort = _mobileSupportedEffort(
                        model,
                        selectedEffort,
                      );
                      if (!model.supportsFastMode) selectedSpeed = 'normal';
                    });
                    onModel(model.id);
                  },
                ),
              const Divider(),
              const ListTile(title: Text('Reasoning Effort')),
              for (final effort
                  in selectedModel?.reasoningEfforts.isNotEmpty == true
                      ? selectedModel!.reasoningEfforts
                      : const <String>['low', 'medium', 'high', 'xhigh'])
                ListTile(
                  minTileHeight: AleraTokens.minTapTarget,
                  title: Text(_mobileLabel(effort)),
                  trailing: effort == selectedEffort
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setModalState(() => selectedEffort = effort);
                    onReasoning(effort);
                  },
                ),
              if (selectedModel?.supportsFastMode == true) ...<Widget>[
                const Divider(),
                const ListTile(title: Text('Speed')),
                for (final speed in const <String>['normal', 'fast'])
                  ListTile(
                    minTileHeight: AleraTokens.minTapTarget,
                    title: Text(speed == 'fast' ? 'Fast' : 'Standard'),
                    subtitle: speed == 'fast'
                        ? const Text('1.5x speed, more usage.')
                        : const Text('Default speed.'),
                    trailing: speed == selectedSpeed
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      setModalState(() => selectedSpeed = speed);
                      onSpeed(speed);
                    },
                  ),
              ],
              if (collaborationModes.isNotEmpty) ...<Widget>[
                const Divider(),
                const ListTile(title: Text('Collaboration Mode')),
                ListTile(
                  minTileHeight: AleraTokens.minTapTarget,
                  title: const Text('Default'),
                  trailing: selectedCollaboration == null
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setModalState(() => selectedCollaboration = null);
                    onCollaboration(null);
                  },
                ),
                for (final value in collaborationModes)
                  ListTile(
                    minTileHeight: AleraTokens.minTapTarget,
                    title: Text(_mobileLabel(value)),
                    trailing: selectedCollaboration == value
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      setModalState(() => selectedCollaboration = value);
                      onCollaboration(value);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _mobileSupportedEffort(MobileCodexModelOption model, String requested) {
  final efforts = model.reasoningEfforts;
  if (efforts.isEmpty || efforts.contains(requested)) return requested;
  final modelDefault = model.defaultReasoningEffort;
  if (modelDefault != null && efforts.contains(modelDefault)) {
    return modelDefault;
  }
  return efforts.first;
}

String _mobileModelLabel(String value) => value
    .replaceFirst(RegExp(r'^GPT-', caseSensitive: false), '')
    .replaceAll('-', ' ');

String _mobileLabel(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('-', ' ')}';
