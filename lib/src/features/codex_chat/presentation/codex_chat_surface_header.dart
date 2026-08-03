part of 'codex_chat_surface.dart';

class _CodexHeader extends StatelessWidget {
  const _CodexHeader({
    required this.onCompact,
    required this.onReview,
    required this.onRename,
    required this.onToggleRawLogs,
  });

  final Future<void> Function() onCompact;
  final Future<void> Function() onReview;
  final VoidCallback onRename;
  final VoidCallback onToggleRawLogs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Wrap(
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AleraIconButton(
            tooltip: 'Compact Context',
            icon: AleraIcons.collapseAll,
            onPressed: () => unawaited(onCompact()),
          ),
          AleraIconButton(
            tooltip: 'Start Review',
            icon: AleraIcons.checks,
            onPressed: () => unawaited(onReview()),
          ),
          AleraIconButton(
            tooltip: 'Rename Thread',
            icon: AleraIcons.edit,
            onPressed: onRename,
          ),
          AleraIconButton(
            tooltip: 'Raw Logs',
            icon: AleraIcons.file,
            onPressed: onToggleRawLogs,
          ),
        ],
      ),
    );
  }
}

String _choiceLabel(String value) => value
    .split('-')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

class _CodexChoiceButton extends StatelessWidget {
  const _CodexChoiceButton({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<String> values;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    onSelected: onChanged,
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final item in values)
        PopupMenuItem<String>(value: item, child: Text(_choiceLabel(item))),
    ],
    child: TextButton.icon(
      onPressed: null,
      icon: const Icon(AleraIcons.chevronDown, size: 14),
      label: Text(label),
    ),
  );
}

class _CodexCatalogButton extends StatelessWidget {
  const _CodexCatalogButton({
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
    tooltip: label,
    onSelected: (name) => onSelected('$prefix$name'),
    itemBuilder: (context) => <PopupMenuEntry<String>>[
      for (final item in items)
        if (item['name']?.toString().trim() case final String name
            when name.isNotEmpty)
          PopupMenuItem<String>(value: name, child: Text(name)),
    ],
    child: TextButton.icon(
      onPressed: null,
      icon: const Icon(AleraIcons.chevronDown, size: 14),
      label: Text(label),
    ),
  );
}

class _CodexCollaborationButton extends StatelessWidget {
  const _CodexCollaborationButton({
    required this.modes,
    required this.value,
    required this.onChanged,
  });

  final List<Map<String, Object?>> modes;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <String>[
      for (final mode in modes)
        if (mode['mode']?.toString().trim() case final String modeName
            when modeName.isNotEmpty)
          modeName,
    ];
    if (options.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Collaboration Mode',
      onSelected: onChanged,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            child: Text(_choiceLabel(option)),
          ),
      ],
      child: TextButton.icon(
        onPressed: null,
        icon: const Icon(AleraIcons.chevronDown, size: 14),
        label: Text(value == null ? 'Collaboration' : _choiceLabel(value!)),
      ),
    );
  }
}

class _CodexMentionButton extends StatelessWidget {
  const _CodexMentionButton({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _askForMention(context),
    icon: const Icon(AleraIcons.chevronDown, size: 14),
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
