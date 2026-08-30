part of 'codex_chat_surface.dart';

class _CodexPermissionEntry extends PopupMenuEntry<String> {
  const _CodexPermissionEntry({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    this.warning = false,
  });

  final String value;
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final bool warning;

  @override
  double get height => AleraTokens.space48 + AleraTokens.space8;

  @override
  bool represents(String? value) => this.value == value;

  @override
  State<_CodexPermissionEntry> createState() => _CodexPermissionEntryState();
}

class _CodexPermissionEntryState extends State<_CodexPermissionEntry> {
  @override
  Widget build(BuildContext context) {
    final accent = widget.warning
        ? AleraTokens.warning
        : AleraTokens.foreground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2 / 2),
      child: Material(
        key: ValueKey<String>('codex-permission-entry-${widget.value}'),
        color: widget.selected ? AleraTokens.accentSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          autofocus: widget.selected,
          onTap: () => Navigator.of(context).pop(widget.value),
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          hoverColor: AleraTokens.accentSubtle,
          focusColor: AleraTokens.accentSubtle,
          highlightColor: AleraTokens.accentSubtle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(widget.icon, size: AleraTokens.iconMd, color: accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: accent),
                      ),
                      Text(
                        widget.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: widget.warning
                              ? AleraTokens.warning
                              : AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.selected)
                  Icon(
                    AleraIcons.check,
                    size: AleraTokens.iconMd,
                    color: accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    child: Material(
      color: widget.selected ? AleraTokens.accentSubtle : Colors.transparent,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        autofocus: widget.selected,
        onTap: () => Navigator.of(context).pop(widget.value),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AleraTokens.radiusLg)),
        ),
        hoverColor: AleraTokens.accentSubtle,
        focusColor: AleraTokens.accentSubtle,
        highlightColor: AleraTokens.accentSubtle,
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
    ),
  );
}
