part of 'codex_chat_surface.dart';

enum CodexComposerCommand {
  newChat('new', 'Start a new Codex chat'),
  clear('clear', 'Clear the current chat and start a new one'),
  compact('compact', 'Compact the current context'),
  review('review', 'Start a code review'),
  plan('plan', 'Toggle plan mode'),
  model('model', 'Choose the active model'),
  permissions('permissions', 'Choose the approval mode'),
  mention('mention', 'Reference a workspace file'),
  skills('skills', 'Attach a skill'),
  apps('apps', 'Attach an app'),
  status('status', 'Show thread status'),
  rename('rename', 'Rename this Codex thread'),
  logs('logs', 'Toggle raw app-server events'),
  resume('resume', 'Resume a previous Codex thread');

  const CodexComposerCommand(this.name, this.description);

  final String name;
  final String description;
}

const codexComposerCommands = CodexComposerCommand.values;

class CodexComposerEntry {
  const CodexComposerEntry.builtin(this.builtin) : savedPrompt = null;

  const CodexComposerEntry.saved(this.savedPrompt) : builtin = null;

  final CodexComposerCommand? builtin;
  final native.CodexSavedPrompt? savedPrompt;

  String get name => builtin?.name ?? savedPrompt!.name;
  String get description => builtin?.description ?? savedPrompt!.description;
  String? get argumentHint => savedPrompt?.argumentHint;
  String get source => builtin != null
      ? 'Built-In'
      : savedPrompt!.scope == native.CodexSavedPromptScope.repo
      ? 'Repo'
      : 'User';

  bool matches(String query) {
    if (query.isEmpty) return true;
    final normalized = query.toLowerCase();
    return name.toLowerCase().contains(normalized) ||
        description.toLowerCase().contains(normalized) ||
        (argumentHint?.toLowerCase().contains(normalized) ?? false);
  }
}

List<CodexComposerEntry> codexComposerEntries(
  List<native.CodexSavedPrompt> savedPrompts, {
  required bool supportsSessions,
}) => <CodexComposerEntry>[
  for (final command in codexComposerCommands)
    if (supportsSessions || command != CodexComposerCommand.resume)
      CodexComposerEntry.builtin(command),
  for (final prompt in savedPrompts) CodexComposerEntry.saved(prompt),
];

class _CodexMentionOverlay extends StatelessWidget {
  const _CodexMentionOverlay({
    required this.paths,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> paths;
  final int selectedIndex;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => _CodexOverlaySurface(
    child: ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      itemCount: paths.length,
      itemBuilder: (context, index) => _CodexOverlayRow(
        selected: index == selectedIndex,
        icon: AleraIcons.fileGeneric,
        title: paths[index],
        onTap: () => onSelected(paths[index]),
      ),
    ),
  );
}

class _CodexCommandOverlay extends StatelessWidget {
  const _CodexCommandOverlay({
    required this.commands,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<CodexComposerEntry> commands;
  final int selectedIndex;
  final ValueChanged<CodexComposerEntry> onSelected;

  @override
  Widget build(BuildContext context) => _CodexOverlaySurface(
    child: ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      itemCount: commands.length,
      itemBuilder: (context, index) {
        final command = commands[index];
        return _CodexOverlayRow(
          selected: index == selectedIndex,
          icon: AleraIcons.chevronRight,
          title: '/${command.name}',
          subtitle: command.description,
          trailing: command.source,
          onTap: () => onSelected(command),
        );
      },
    ),
  );
}

class _CodexOverlaySurface extends StatelessWidget {
  const _CodexOverlaySurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(
      maxHeight: AleraTokens.codexComposerOverlayMaxHeight,
    ),
    margin: const EdgeInsets.only(bottom: AleraTokens.space4),
    decoration: BoxDecoration(
      color: AleraTokens.surfaceVariant,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      border: Border.all(color: AleraTokens.border),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: AleraTokens.shadowSoft,
          blurRadius: AleraTokens.space8,
          offset: Offset(0, -AleraTokens.space2),
        ),
      ],
    ),
    child: child,
  );
}

class _CodexOverlayRow extends StatelessWidget {
  const _CodexOverlayRow({
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    mouseCursor: SystemMouseCursors.click,
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    child: ColoredBox(
      color: selected ? AleraTokens.accentSubtle : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: AleraTokens.iconMd,
              color: selected
                  ? AleraTokens.accent
                  : AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? AleraTokens.accent
                          : AleraTokens.foreground,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CodexCatalogPickerDialog extends StatefulWidget {
  const _CodexCatalogPickerDialog({
    required this.title,
    required this.items,
    required this.searchHint,
  });

  final String title;
  final List<Map<String, Object?>> items;
  final String searchHint;

  @override
  State<_CodexCatalogPickerDialog> createState() =>
      _CodexCatalogPickerDialogState();
}

class _CodexCatalogPickerDialogState extends State<_CodexCatalogPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where((item) {
          if (_query.isEmpty) return true;
          final text = item.values.join(' ').toLowerCase();
          return text.contains(_query.toLowerCase());
        })
        .toList(growable: false);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AleraTokens.dialogCompactWidth,
          maxWidth: AleraTokens.dialogWideWidth,
          maxHeight: AleraTokens.dialogMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space16,
                AleraTokens.space16,
                AleraTokens.space8,
                AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  AleraIconButton(
                    tooltip: 'Close',
                    icon: AleraIcons.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(hintText: widget.searchHint),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: AleraTokens.space8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    dense: true,
                    title: Text(_catalogName(item)),
                    subtitle: Text(_catalogDescription(item)),
                    trailing: Text(_catalogScope(item)),
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _catalogName(Map<String, Object?> item) {
  final interface = item['interface'];
  if (interface is Map) {
    final displayName = interface['displayName']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
  }
  for (final key in <String>['slug', 'name', 'id', 'appId']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return 'Unknown';
}

String _catalogDescription(Map<String, Object?> item) {
  final interface = item['interface'];
  if (interface is Map) {
    final description = interface['shortDescription']?.toString().trim();
    if (description != null && description.isNotEmpty) return description;
  }
  for (final key in <String>['shortDescription', 'description', 'name']) {
    final value = item[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

String _catalogScope(Map<String, Object?> item) =>
    item['scope']?.toString().trim() ?? '';
