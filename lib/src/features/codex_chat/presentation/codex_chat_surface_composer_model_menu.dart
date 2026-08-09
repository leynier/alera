part of 'codex_chat_surface.dart';

class _CodexModelConfigurationControl extends StatefulWidget {
  const _CodexModelConfigurationControl({
    required this.state,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onCollaborationChanged,
  });

  final CodexChatState state;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String?> onCollaborationChanged;

  @override
  State<_CodexModelConfigurationControl> createState() =>
      _CodexModelConfigurationControlState();
}

class _CodexModelConfigurationControlState
    extends State<_CodexModelConfigurationControl> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final model = state.selectedModelOption;
    final efforts = model?.reasoningEfforts.isNotEmpty == true
        ? model!.reasoningEfforts
        : const <String>['low', 'medium', 'high', 'xhigh'];
    final collaborationModes = <String>{
      for (final entry in state.collaborationModes)
        if (entry['mode']?.toString().trim() case final String mode
            when mode.isNotEmpty &&
                mode.toLowerCase() != 'default' &&
                mode.toLowerCase() != 'plan')
          mode,
    }.toList(growable: false);
    final selectedCollaboration =
        state.collaborationMode == null || state.collaborationMode == 'plan'
        ? 'default'
        : state.collaborationMode!;
    return MenuAnchor(
      controller: _menuController,
      style: _codexMenuStyle,
      menuChildren: <Widget>[
        _CodexConfigurationSubmenuButton<CodexModelOption>(
          choices: state.models,
          selected: model,
          labelFor: (option) => option.label,
          onSelected: (option) {
            widget.onModelChanged(option.id);
          },
          child: _CodexConfigurationRow(
            label: 'Model',
            value:
                model?.label ??
                codexModelDisplayLabel(state.selectedModel ?? 'Default'),
          ),
        ),
        _CodexConfigurationSubmenuButton<String>(
          choices: efforts,
          selected: state.reasoningEffort,
          labelFor: _choiceLabel,
          onSelected: (effort) {
            widget.onReasoningChanged(effort);
          },
          child: _CodexConfigurationRow(
            label: 'Effort',
            value: _choiceLabel(state.reasoningEffort),
          ),
        ),
        if (model?.supportsFastMode == true)
          _CodexConfigurationSubmenuButton<String>(
            choices: const <String>['normal', 'fast'],
            selected: state.speedMode,
            labelFor: (speed) => speed == 'normal' ? 'Standard' : 'Fast',
            onSelected: (speed) {
              widget.onSpeedChanged(speed);
            },
            child: _CodexConfigurationRow(
              label: 'Speed',
              value: state.speedMode == 'fast' ? 'Fast' : 'Standard',
            ),
          ),
        if (collaborationModes.isNotEmpty)
          _CodexConfigurationSubmenuButton<String>(
            choices: <String>['default', ...collaborationModes],
            selected: selectedCollaboration,
            labelFor: (mode) =>
                mode == 'default' ? 'Default' : _choiceLabel(mode),
            onSelected: (mode) {
              widget.onCollaborationChanged(mode == 'default' ? null : mode);
            },
            child: _CodexConfigurationRow(
              label: 'Mode',
              value: selectedCollaboration == 'default'
                  ? 'Default'
                  : _choiceLabel(selectedCollaboration),
            ),
          ),
      ],
      builder: (context, anchorController, child) => InkWell(
        key: const ValueKey<String>('codex-model-configuration'),
        onTap: anchorController.isOpen
            ? anchorController.close
            : anchorController.open,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        child: _CodexComposerChip(
          leadingIcon: state.speedMode == 'fast' ? AleraIcons.speedFast : null,
          label:
              model?.label ??
              codexModelDisplayLabel(state.selectedModel ?? 'Model'),
          secondaryLabel: _choiceLabel(state.reasoningEffort),
        ),
      ),
    );
  }
}

class _CodexConfigurationSubmenuButton<T> extends StatelessWidget {
  const _CodexConfigurationSubmenuButton({
    required this.choices,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
    required this.child,
  });

  final List<T> choices;
  final T? selected;
  final String Function(T choice) labelFor;
  final ValueChanged<T> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    clipBehavior: Clip.hardEdge,
    child: InkWell(
      onTap: choices.isEmpty ? null : () => unawaited(_showChoices(context)),
      mouseCursor: choices.isEmpty
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: SizedBox(
        height: AleraTokens.codexMenuItemHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          child: Row(
            children: <Widget>[
              Expanded(child: child),
              const Icon(Icons.arrow_right, size: AleraTokens.iconMd),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showChoices(BuildContext itemContext) async {
    final button = itemContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(itemContext).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final anchor = origin & button.size;
    final choice = await showMenu<T>(
      context: itemContext,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      constraints: const BoxConstraints(
        minWidth: AleraTokens.contextMenuWidth - AleraTokens.space32,
        maxWidth: AleraTokens.contextMenuWidth,
      ),
      color: AleraTokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.border),
      ),
      clipBehavior: Clip.hardEdge,
      menuPadding: const EdgeInsets.all(AleraTokens.space8),
      items: <PopupMenuEntry<T>>[
        for (final option in choices)
          _CodexConfigurationPopupEntry<T>(
            value: option,
            label: labelFor(option),
            selected: option == selected,
          ),
      ],
    );
    if (choice != null) onSelected(choice);
  }
}

class _CodexConfigurationPopupEntry<T> extends PopupMenuEntry<T> {
  const _CodexConfigurationPopupEntry({
    required this.value,
    required this.label,
    required this.selected,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => AleraTokens.codexMenuItemHeight + AleraTokens.space4;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<_CodexConfigurationPopupEntry<T>> createState() =>
      _CodexConfigurationPopupEntryState<T>();
}

class _CodexConfigurationPopupEntryState<T>
    extends State<_CodexConfigurationPopupEntry<T>> {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
    child: SizedBox(
      height: AleraTokens.codexMenuItemHeight,
      child: Material(
        color: widget.selected ? AleraTokens.accentSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(widget.value),
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          hoverColor: AleraTokens.accentSubtle,
          focusColor: AleraTokens.accentSubtle,
          highlightColor: AleraTokens.accentSubtle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(widget.label)),
                if (widget.selected)
                  const Icon(AleraIcons.check, size: AleraTokens.iconMd),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CodexConfigurationRow extends StatelessWidget {
  const _CodexConfigurationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Text(label),
      const SizedBox(width: AleraTokens.space16),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AleraTokens.foregroundMuted),
        ),
      ),
    ],
  );
}

final MenuStyle _codexMenuStyle = MenuStyle(
  minimumSize: const WidgetStatePropertyAll<Size>(
    Size(AleraTokens.masterDetailDefaultWidth, 0),
  ),
  backgroundColor: const WidgetStatePropertyAll<Color>(
    AleraTokens.surfaceElevated,
  ),
  shape: WidgetStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      side: const BorderSide(color: AleraTokens.border),
    ),
  ),
  padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.all(AleraTokens.space8),
  ),
  mouseCursor: const WidgetStatePropertyAll<MouseCursor>(
    SystemMouseCursors.click,
  ),
);

class _CodexFullAccessDialog extends StatelessWidget {
  const _CodexFullAccessDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    constraints: const BoxConstraints(
      maxWidth: AleraTokens.contextMenuWidth * 2,
    ),
    title: const Row(
      children: <Widget>[
        Icon(AleraIcons.warning, color: AleraTokens.error),
        SizedBox(width: AleraTokens.space8),
        Expanded(child: Text('Turn On Full Access?')),
      ],
    ),
    content: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Codex will be able to run commands, use the internet, and create and edit files anywhere on this computer without your permission.',
        ),
        SizedBox(height: AleraTokens.space16),
        _CodexAccessCapability(
          icon: AleraIcons.folder,
          title: 'Files And Folders',
          description:
              'Read, create, modify, upload, or delete files anywhere.',
        ),
        _CodexAccessCapability(
          icon: AleraIcons.terminal,
          title: 'Terminal Commands',
          description: 'Run commands, install software, and change settings.',
        ),
        _CodexAccessCapability(
          icon: AleraIcons.public,
          title: 'Internet And Connected Apps',
          description: 'Access websites, send data, and use enabled apps.',
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(true),
        style: FilledButton.styleFrom(
          backgroundColor: AleraTokens.error,
          foregroundColor: AleraTokens.onError,
        ),
        icon: const Icon(AleraIcons.warning),
        label: const Text('Confirm'),
      ),
    ],
  );
}

class _CodexAccessCapability extends StatelessWidget {
  const _CodexAccessCapability({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
    child: Row(
      children: <Widget>[
        Icon(icon, size: AleraTokens.iconLg, color: AleraTokens.info),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              Text(
                description,
                style: const TextStyle(color: AleraTokens.foregroundMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
