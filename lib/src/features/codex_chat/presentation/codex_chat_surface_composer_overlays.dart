part of 'codex_chat_surface.dart';

enum CodexComposerCommand {
  goal('goal', 'Set or manage a long-running goal'),
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

  IconData get icon => switch (this) {
    CodexComposerCommand.goal => Icons.track_changes_outlined,
    CodexComposerCommand.newChat ||
    CodexComposerCommand.clear => AleraIcons.forward,
    CodexComposerCommand.resume => AleraIcons.restore,
    CodexComposerCommand.compact => AleraIcons.loading,
    CodexComposerCommand.review => AleraIcons.agent,
    CodexComposerCommand.plan => AleraIcons.plan,
    CodexComposerCommand.model => AleraIcons.ai,
    CodexComposerCommand.permissions => AleraIcons.secure,
    CodexComposerCommand.mention => AleraIcons.file,
    CodexComposerCommand.skills => AleraIcons.package,
    CodexComposerCommand.apps => AleraIcons.public,
    CodexComposerCommand.status => AleraIcons.info,
    CodexComposerCommand.rename => AleraIcons.edit,
    CodexComposerCommand.logs => AleraIcons.terminal,
  };
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
  required bool supportsGoals,
}) => <CodexComposerEntry>[
  for (final command in codexComposerCommands)
    if ((supportsSessions || command != CodexComposerCommand.resume) &&
        (supportsGoals || command != CodexComposerCommand.goal))
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
    child: _CodexNavigableOverlayList(
      selectedIndex: selectedIndex,
      itemCount: paths.length,
      itemBuilder: (context, index) => _CodexOverlayRow(
        selected: index == selectedIndex,
        leading: AleraFileIcon(
          pathOrName: paths[index],
          kind: AleraFileIconKind.file,
          size: AleraTokens.iconMd,
        ),
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
    child: _CodexNavigableOverlayList(
      selectedIndex: selectedIndex,
      itemCount: commands.length,
      itemBuilder: (context, index) {
        final command = commands[index];
        return _CodexOverlayRow(
          selected: index == selectedIndex,
          icon: command.builtin?.icon ?? AleraIcons.package,
          title: command.builtin == null ? command.name : '/${command.name}',
          subtitle: command.description,
          trailing: command.source,
          onTap: () => onSelected(command),
        );
      },
    ),
  );
}

class _CodexCatalogOverlay extends StatelessWidget {
  const _CodexCatalogOverlay({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<CodexDraftItem> items;
  final int selectedIndex;
  final ValueChanged<CodexDraftItem> onSelected;

  @override
  Widget build(BuildContext context) => _CodexOverlaySurface(
    child: _CodexNavigableOverlayList(
      selectedIndex: selectedIndex,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _CodexOverlayRow(
          selected: index == selectedIndex,
          leading: item.kind == CodexDraftItemKind.skill
              ? const Icon(
                  AleraIcons.package,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundMuted,
                )
              : _CodexCatalogAppIcon(url: item.iconUrl),
          title: item.name,
          subtitle: item.kind == CodexDraftItemKind.skill ? 'Skill' : 'App',
          subtitleTextAlign: TextAlign.right,
          trailing: item.kind == CodexDraftItemKind.skill ? 'Personal' : 'App',
          onTap: () => onSelected(item),
        );
      },
    ),
  );
}

class _CodexNavigableOverlayList extends StatefulWidget {
  const _CodexNavigableOverlayList({
    required this.selectedIndex,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int selectedIndex;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;

  @override
  State<_CodexNavigableOverlayList> createState() =>
      _CodexNavigableOverlayListState();
}

class _CodexNavigableOverlayListState
    extends State<_CodexNavigableOverlayList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _CodexNavigableOverlayList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex ||
        widget.itemCount != oldWidget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelection());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _revealSelection() {
    if (!mounted || !_scrollController.hasClients || widget.itemCount == 0) {
      return;
    }
    final position = _scrollController.position;
    final itemTop =
        AleraTokens.space4 +
        widget.selectedIndex * AleraTokens.codexMenuItemHeight;
    final itemBottom = itemTop + AleraTokens.codexMenuItemHeight;
    var target = position.pixels;
    if (itemTop < position.pixels) {
      target = itemTop - AleraTokens.space4;
    } else if (itemBottom > position.pixels + position.viewportDimension) {
      target = itemBottom - position.viewportDimension + AleraTokens.space4;
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    unawaited(
      _scrollController.animateTo(
        target,
        duration: AleraTokens.durationFast,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const ValueKey<String>('codex-composer-overlay-scroll'),
    controller: _scrollController,
    shrinkWrap: true,
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
    itemExtent: AleraTokens.codexMenuItemHeight,
    itemCount: widget.itemCount,
    itemBuilder: widget.itemBuilder,
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
    required this.title,
    required this.onTap,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleTextAlign = TextAlign.left,
    this.trailing,
  }) : assert(icon != null || leading != null);

  final bool selected;
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final TextAlign subtitleTextAlign;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AleraTokens.accentSubtle : Colors.transparent,
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    clipBehavior: Clip.hardEdge,
    child: InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            leading ??
                Icon(
                  icon,
                  size: AleraTokens.iconMd,
                  color: selected
                      ? AleraTokens.accent
                      : AleraTokens.foregroundMuted,
                ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected ? AleraTokens.accent : AleraTokens.foreground,
                ),
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  subtitle!,
                  textAlign: subtitleTextAlign,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ],
            if (trailing != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space8),
              Text(
                trailing!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
