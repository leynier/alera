part of 'codex_chat_surface.dart';

class _CodexComposerControls extends StatelessWidget {
  const _CodexComposerControls({
    required this.modelMenu,
    required this.reasoningMenu,
    required this.state,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onPermissionChanged,
    required this.onPlanChanged,
    required this.onCollaborationChanged,
    required this.onAddAttachment,
    required this.onPaste,
    required this.onDraftItemSelected,
    required this.onCommand,
  });

  final GlobalKey<PopupMenuButtonState<String>> modelMenu;
  final GlobalKey<PopupMenuButtonState<String>> reasoningMenu;
  final CodexChatState state;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String> onPermissionChanged;
  final ValueChanged<bool> onPlanChanged;
  final ValueChanged<String?> onCollaborationChanged;
  final Future<void> Function() onAddAttachment;
  final Future<void> Function() onPaste;
  final ValueChanged<CodexDraftItem> onDraftItemSelected;
  final ValueChanged<CodexComposerCommand> onCommand;

  @override
  Widget build(BuildContext context) {
    final selectedModel = state.selectedModelOption;
    final efforts = selectedModel?.reasoningEfforts.isNotEmpty == true
        ? selectedModel!.reasoningEfforts
        : const <String>['low', 'medium', 'high', 'xhigh'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PopupMenuButton<String>(
          tooltip: 'Add Photos And Files',
          onSelected: (value) => _handleAddAction(context, value),
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem(
              value: 'file',
              child: Text('Add Photos And Files'),
            ),
            const PopupMenuItem(
              value: 'paste',
              child: Text('Paste From Clipboard'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'skill', child: Text('Add Skill')),
            const PopupMenuItem(value: 'app', child: Text('Add App')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'review', child: Text('Start Review')),
            const PopupMenuItem(
              value: 'compact',
              child: Text('Compact Context'),
            ),
            if (state.supportsSessions) ...const <PopupMenuEntry<String>>[
              PopupMenuDivider(),
              PopupMenuItem(value: 'resume', child: Text('Resume Thread')),
              PopupMenuItem(value: 'new', child: Text('Start New Chat')),
              PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
            ],
          ],
          child: const Padding(
            padding: EdgeInsets.all(AleraTokens.space4),
            child: Icon(
              AleraIcons.add,
              size: AleraTokens.iconXl,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        const SizedBox(width: AleraTokens.space4),
        PopupMenuButton<String>(
          key: modelMenu,
          tooltip: 'Choose Model',
          constraints: const BoxConstraints(
            minWidth: AleraTokens.contextMenuWidth,
          ),
          initialValue: state.selectedModel,
          onSelected: onModelChanged,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _CodexMenuHeader('Select Model'),
            for (final model in state.models)
              _CodexDropdownEntry<String>(
                value: model.id,
                label: model.label,
                selected: model.id == state.selectedModel,
              ),
          ],
          child: _CodexComposerChip(
            label: selectedModel?.label ?? state.selectedModel ?? 'Model',
          ),
        ),
        const SizedBox(width: AleraTokens.space6),
        PopupMenuButton<String>(
          key: reasoningMenu,
          tooltip: 'Select Reasoning Effort',
          initialValue: state.reasoningEffort,
          onSelected: onReasoningChanged,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _CodexMenuHeader('Select Reasoning Effort'),
            for (final effort in efforts)
              _CodexDropdownEntry<String>(
                value: effort,
                label: _choiceLabel(effort),
                selected: effort == state.reasoningEffort,
              ),
          ],
          child: _CodexComposerChip(label: _choiceLabel(state.reasoningEffort)),
        ),
        if (selectedModel?.supportsFastMode == true) ...<Widget>[
          const SizedBox(width: AleraTokens.space6),
          PopupMenuButton<String>(
            tooltip: 'Select Speed Mode',
            initialValue: state.speedMode,
            onSelected: onSpeedChanged,
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              _CodexMenuHeader('Select Speed Mode'),
              for (final mode in const <String>['normal', 'fast'])
                _CodexDropdownEntry<String>(
                  value: mode,
                  label: _choiceLabel(mode),
                  selected: mode == state.speedMode,
                ),
            ],
            child: _CodexComposerChip(label: _choiceLabel(state.speedMode)),
          ),
        ],
        const SizedBox(width: AleraTokens.space6),
        PopupMenuButton<String>(
          tooltip: 'Choose Approval Mode',
          initialValue: state.permissionMode,
          onSelected: onPermissionChanged,
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            _CodexMenuHeader('Select Approval Mode'),
            _CodexDropdownEntry<String>(
              value: 'on-request',
              label: 'Ask For Approval',
              selected: state.permissionMode == 'on-request',
            ),
            if (state.supportsAutoReview)
              _CodexDropdownEntry<String>(
                value: 'auto-review',
                label: 'Approve For Me',
                selected: state.permissionMode == 'auto-review',
              ),
            _CodexDropdownEntry<String>(
              value: 'never',
              label: 'Full Access',
              selected: state.permissionMode == 'never',
            ),
          ],
          child: _CodexComposerChip(
            label: _codexPermissionModeLabel(state.permissionMode),
            highlight: state.permissionMode == 'never',
          ),
        ),
        const SizedBox(width: AleraTokens.space6),
        InkWell(
          onTap: () => onPlanChanged(!state.planMode),
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            child: Text(
              'Plan',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: state.planMode
                    ? AleraTokens.info
                    : AleraTokens.foregroundFaint,
                fontWeight: state.planMode ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
        if (state.collaborationModes.isNotEmpty)
          _CodexCollaborationMenu(
            state: state,
            onChanged: onCollaborationChanged,
          ),
      ],
    );
  }

  Future<void> _handleAddAction(BuildContext context, String value) async {
    switch (value) {
      case 'file':
        await onAddAttachment();
      case 'paste':
        await onPaste();
      case 'skill':
        await _pickCatalog(context, skill: true);
      case 'app':
        await _pickCatalog(context, skill: false);
      case 'review':
        onCommand(CodexComposerCommand.review);
      case 'compact':
        onCommand(CodexComposerCommand.compact);
      case 'resume':
        onCommand(CodexComposerCommand.resume);
      case 'new':
        onCommand(CodexComposerCommand.newChat);
      case 'clear':
        onCommand(CodexComposerCommand.clear);
    }
  }

  Future<void> _pickCatalog(BuildContext context, {required bool skill}) async {
    final items = skill ? state.skills : state.apps;
    if (items.isEmpty) return;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CodexCatalogPickerDialog(
        title: skill ? 'Select A Skill' : 'Select An App',
        items: items,
        searchHint: skill ? 'Filter Skills' : 'Filter Apps',
      ),
    );
    if (selected == null) return;
    final name = _catalogName(selected);
    if (skill) {
      final path = selected['path']?.toString().trim() ?? '';
      if (path.isEmpty) return;
      onDraftItemSelected(
        CodexDraftItem(
          id: 'skill-$path',
          kind: CodexDraftItemKind.skill,
          name: name,
          path: path,
        ),
      );
      return;
    }
    final connector = _catalogConnector(selected);
    if (connector == null) return;
    onDraftItemSelected(
      CodexDraftItem(
        id: 'app-$connector',
        kind: CodexDraftItemKind.app,
        name: name,
        path: connector,
        tokenText: '\$$name',
      ),
    );
  }
}

class _CodexComposerChip extends StatelessWidget {
  const _CodexComposerChip({required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space8,
      vertical: AleraTokens.space4,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: highlight
                ? AleraTokens.warning
                : AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(width: AleraTokens.space4),
        const Icon(
          AleraIcons.chevronDown,
          size: AleraTokens.iconMd,
          color: AleraTokens.foregroundFaint,
        ),
      ],
    ),
  );
}

class _CodexMenuHeader extends PopupMenuItem<String> {
  _CodexMenuHeader(String label)
    : super(
        enabled: false,
        height: AleraTokens.space32,
        child: Text(label, style: AleraTokens.labelFaintStyle),
      );
}

class _CodexDropdownEntry<T> extends PopupMenuEntry<T> {
  const _CodexDropdownEntry({
    required this.value,
    required this.label,
    required this.selected,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => AleraTokens.codexMenuItemHeight;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<_CodexDropdownEntry<T>> createState() => _CodexDropdownEntryState<T>();
}

class _CodexDropdownEntryState<T> extends State<_CodexDropdownEntry<T>> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2 / 2),
    child: InkWell(
      autofocus: widget.selected,
      onTap: () => Navigator.of(context).pop(widget.value),
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(widget.label)),
            if (widget.selected)
              const Icon(AleraIcons.check, size: AleraTokens.iconLg),
          ],
        ),
      ),
    ),
  );
}

class _CodexCollaborationMenu extends StatelessWidget {
  const _CodexCollaborationMenu({required this.state, required this.onChanged});

  final CodexChatState state;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final modes = <String>[
      for (final mode in state.collaborationModes)
        if (mode['mode']?.toString().trim() case final String name
            when name.isNotEmpty)
          name,
    ];
    return PopupMenuButton<String>(
      tooltip: 'Collaboration Mode',
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final mode in modes)
          _CodexDropdownEntry<String>(
            value: mode,
            label: _choiceLabel(mode),
            selected: mode == state.collaborationMode,
          ),
      ],
      child: _CodexComposerChip(
        label: state.collaborationMode == null
            ? 'Collaboration'
            : _choiceLabel(state.collaborationMode!),
      ),
    );
  }
}

String? _catalogConnector(Map<String, Object?> item) {
  final path = item['path']?.toString().trim();
  if (path != null && path.startsWith('app://')) return path;
  for (final key in <String>['connectorId', 'connector_id', 'appId', 'id']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return 'app://$value';
  }
  return null;
}

String _choiceLabel(String value) => value
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

String _codexPermissionModeLabel(String mode) => switch (mode) {
  'auto-review' => 'Approve For Me',
  'never' => 'Full Access',
  _ => 'Ask For Approval',
};
