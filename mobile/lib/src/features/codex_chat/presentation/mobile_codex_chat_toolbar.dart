part of 'mobile_codex_chat_screen.dart';

class _MobileCodexToolbar extends StatelessWidget {
  const _MobileCodexToolbar({
    required this.state,
    required this.onModel,
    required this.onReasoning,
    required this.onSpeed,
    required this.onPermission,
    required this.onPlan,
    required this.onCollaboration,
    required this.onInsertToken,
    required this.onCompact,
    required this.onReview,
    required this.onRename,
  });

  final MobileCodexState state;
  final ValueChanged<String?> onModel;
  final ValueChanged<String> onReasoning;
  final ValueChanged<String> onSpeed;
  final ValueChanged<String> onPermission;
  final ValueChanged<bool> onPlan;
  final ValueChanged<String?> onCollaboration;
  final ValueChanged<String> onInsertToken;
  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) => Material(
    color: AleraTokens.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            DropdownButton<String>(
              value:
                  state.models.any((model) => model.id == state.selectedModel)
                  ? state.selectedModel
                  : null,
              hint: const Text('Model'),
              items: <DropdownMenuItem<String>>[
                for (final model in state.models)
                  DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label),
                  ),
              ],
              onChanged: onModel,
            ),
            if (state.contextUsed != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space4,
                ),
                child: Text(
                  'Context: ${state.contextUsed}/${state.contextLimit ?? '?'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            _MobileCatalogButton(
              label: 'Skills',
              prefix: '/skill ',
              items: state.skills,
              onSelected: onInsertToken,
            ),
            _MobileCatalogButton(
              label: 'Apps',
              prefix: '/app ',
              items: state.apps,
              onSelected: onInsertToken,
            ),
            _MobileMentionButton(onSelected: onInsertToken),
            _MobileChoice(
              label: 'Reasoning: ${_mobileLabel(state.reasoningEffort)}',
              values: _reasoningValues(state),
              onSelected: onReasoning,
            ),
            _MobileChoice(
              label: 'Speed: ${_mobileLabel(state.speedMode)}',
              values:
                  state.models
                          .where((model) => model.id == state.selectedModel)
                          .firstOrNull
                          ?.supportsFastMode ==
                      true
                  ? const <String>['normal', 'fast']
                  : const <String>['normal'],
              onSelected: onSpeed,
            ),
            _MobileChoice(
              label: 'Permission: ${_mobileLabel(state.permissionMode)}',
              values: const <String>['on-request', 'never'],
              onSelected: onPermission,
            ),
            FilterChip(
              label: const Text('Plan'),
              selected: state.planMode,
              onSelected: onPlan,
            ),
            if (state.collaborationModes.isNotEmpty)
              _MobileChoice(
                label: state.collaborationMode == null
                    ? 'Collaboration'
                    : _mobileLabel(state.collaborationMode!),
                values: <String>[
                  for (final mode in state.collaborationModes)
                    if (mode['mode']?.toString().trim()
                        case final String modeName when modeName.isNotEmpty)
                      modeName,
                ],
                onSelected: onCollaboration,
              ),
            IconButton(
              tooltip: 'Compact Context',
              onPressed: () => unawaited(onCompact()),
              icon: const Icon(Icons.compress),
            ),
            IconButton(
              tooltip: 'Start Review',
              onPressed: () => unawaited(onReview()),
              icon: const Icon(Icons.rate_review_outlined),
            ),
            IconButton(
              tooltip: 'Rename Thread',
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    ),
  );
}

List<String> _reasoningValues(MobileCodexState state) {
  final selected = state.models
      .where((model) => model.id == state.selectedModel)
      .firstOrNull
      ?.reasoningEfforts;
  return selected == null || selected.isEmpty
      ? const <String>['low', 'medium', 'high', 'xhigh']
      : selected;
}

class _MobileCatalogButton extends StatelessWidget {
  const _MobileCatalogButton({
    required this.label,
    required this.prefix,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final String prefix;
  final List<Map<String, Object?>> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    enabled: items.isNotEmpty,
    onSelected: (name) => onSelected('$prefix$name'),
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final item in items)
        if (item['name']?.toString().trim() case final String name
            when name.isNotEmpty)
          PopupMenuItem<String>(value: name, child: Text(name)),
    ],
    child: TextButton.icon(
      onPressed: null,
      icon: const Icon(Icons.arrow_drop_down),
      label: Text(label),
    ),
  );
}

class _MobileMentionButton extends StatelessWidget {
  const _MobileMentionButton({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _askForMention(context),
    icon: const Icon(Icons.arrow_drop_down),
    label: const Text('Mentions'),
  );

  Future<void> _askForMention(BuildContext context) async {
    final input = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mention Workspace File'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'lib/main.dart'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Insert'),
          ),
        ],
      ),
    );
    input.dispose();
    if (path != null && path.trim().isNotEmpty) onSelected('@${path.trim()}');
  }
}

class _MobileChoice extends StatelessWidget {
  const _MobileChoice({
    required this.label,
    required this.values,
    required this.onSelected,
  });

  final String label;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    onSelected: onSelected,
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final value in values)
        PopupMenuItem<String>(value: value, child: Text(_mobileLabel(value))),
    ],
    child: TextButton.icon(
      onPressed: null,
      icon: const Icon(Icons.arrow_drop_down),
      label: Text(label),
    ),
  );
}
