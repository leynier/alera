part of 'mobile_codex_chat_screen.dart';

class _MobileModelMenuButton extends StatelessWidget {
  const _MobileModelMenuButton({
    super.key,
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
    final selection = _MobileModelMenuSelection.fromState(state, selected);
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) =>
            _buildMenu(selection, setModalState),
      ),
    );
  }

  Widget _buildMenu(
    _MobileModelMenuSelection selection,
    StateSetter setModalState,
  ) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: <Widget>[
        ..._modelOptions(selection, setModalState),
        ..._reasoningOptions(selection, setModalState),
        if (selection.model?.supportsFastMode == true)
          ..._speedOptions(selection, setModalState),
        if (selection.collaborationModes.isNotEmpty)
          ..._collaborationOptions(selection, setModalState),
      ],
    ),
  );

  List<Widget> _modelOptions(
    _MobileModelMenuSelection selection,
    StateSetter setModalState,
  ) => _mobileModelMenuSection(
    title: 'Model',
    first: true,
    options: <Widget>[
      for (final model in state.models)
        _mobileModelMenuOption(
          label: _mobileModelLabel(model.label),
          selected: model.id == selection.model?.id,
          onTap: () => _selectModel(setModalState, selection, model),
        ),
    ],
  );

  List<Widget> _reasoningOptions(
    _MobileModelMenuSelection selection,
    StateSetter setModalState,
  ) => _mobileModelMenuSection(
    title: 'Reasoning Effort',
    options: <Widget>[
      for (final effort in selection.reasoningEfforts)
        _mobileModelMenuOption(
          label: _mobileLabel(effort),
          selected: effort == selection.effort,
          onTap: () => _selectReasoning(setModalState, selection, effort),
        ),
    ],
  );

  List<Widget> _speedOptions(
    _MobileModelMenuSelection selection,
    StateSetter setModalState,
  ) => _mobileModelMenuSection(
    title: 'Speed',
    options: <Widget>[
      for (final speed in const <String>['normal', 'fast'])
        _mobileModelMenuOption(
          label: speed == 'fast' ? 'Fast' : 'Standard',
          subtitle: speed == 'fast'
              ? '1.5x speed, more usage.'
              : 'Default speed.',
          selected: speed == selection.speed,
          onTap: () => _selectSpeed(setModalState, selection, speed),
        ),
    ],
  );

  List<Widget> _collaborationOptions(
    _MobileModelMenuSelection selection,
    StateSetter setModalState,
  ) => _mobileModelMenuSection(
    title: 'Collaboration Mode',
    options: <Widget>[
      _mobileModelMenuOption(
        label: 'Default',
        selected: selection.collaboration == null,
        onTap: () => _selectCollaboration(setModalState, selection, null),
      ),
      for (final value in selection.collaborationModes)
        _mobileModelMenuOption(
          label: _mobileLabel(value),
          selected: selection.collaboration == value,
          onTap: () => _selectCollaboration(setModalState, selection, value),
        ),
    ],
  );

  void _selectModel(
    StateSetter setModalState,
    _MobileModelMenuSelection selection,
    MobileCodexModelOption model,
  ) {
    setModalState(() => selection.selectModel(model));
    onModel(model.id);
  }

  void _selectReasoning(
    StateSetter setModalState,
    _MobileModelMenuSelection selection,
    String effort,
  ) {
    setModalState(() => selection.effort = effort);
    onReasoning(effort);
  }

  void _selectSpeed(
    StateSetter setModalState,
    _MobileModelMenuSelection selection,
    String speed,
  ) {
    setModalState(() => selection.speed = speed);
    onSpeed(speed);
  }

  void _selectCollaboration(
    StateSetter setModalState,
    _MobileModelMenuSelection selection,
    String? collaboration,
  ) {
    setModalState(() => selection.collaboration = collaboration);
    onCollaboration(collaboration);
  }
}

class _MobileModelMenuSelection {
  _MobileModelMenuSelection.fromState(MobileCodexState state, this.model)
    : effort = state.reasoningEffort,
      speed = state.speedMode,
      collaboration = state.collaborationMode,
      collaborationModes = <String>{
        for (final mode in state.collaborationModes)
          if (mode['mode']?.toString().trim() case final String value
              when value.isNotEmpty &&
                  value.toLowerCase() != 'default' &&
                  value.toLowerCase() != 'plan')
            value,
      }.toList(growable: false);

  MobileCodexModelOption? model;
  String effort;
  String speed;
  String? collaboration;
  final List<String> collaborationModes;

  List<String> get reasoningEfforts =>
      model?.reasoningEfforts.isNotEmpty == true
      ? model!.reasoningEfforts
      : const <String>['low', 'medium', 'high', 'xhigh'];

  void selectModel(MobileCodexModelOption value) {
    model = value;
    effort = _mobileSupportedEffort(value, effort);
    if (!value.supportsFastMode) speed = 'normal';
  }
}

List<Widget> _mobileModelMenuSection({
  required String title,
  required List<Widget> options,
  bool first = false,
}) => <Widget>[
  if (!first) const Divider(),
  ListTile(title: Text(title)),
  ...options,
];

Widget _mobileModelMenuOption({
  required String label,
  String? subtitle,
  required bool selected,
  required VoidCallback onTap,
}) => ListTile(
  minTileHeight: AleraTokens.minTapTarget,
  title: Text(label),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: selected ? const Icon(Icons.check) : null,
  onTap: onTap,
);

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
