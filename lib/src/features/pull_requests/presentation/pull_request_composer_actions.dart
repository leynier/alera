part of 'pull_request_composer.dart';

/// Blocks [child] with a dimmed barrier only - no loading chip.
class _AiDimmedBlock extends StatelessWidget {
  const _AiDimmedBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: AbsorbPointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AleraTokens.barrierDark,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Blocks [child] with the Source Control-style AI loading treatment.
class _AiGeneratingOverlay extends StatelessWidget {
  const _AiGeneratingOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: AbsorbPointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AleraTokens.barrierDark,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AleraTokens.surfaceElevated,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    border: Border.all(color: AleraTokens.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space12,
                      vertical: AleraTokens.space8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space8),
                        Text(
                          'Generating with AI',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiPullRequestButton extends StatefulWidget {
  const _AiPullRequestButton({
    required this.generating,
    required this.canGenerate,
    required this.onGenerate,
    required this.onCancel,
  });

  final bool generating;
  final bool canGenerate;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

  @override
  State<_AiPullRequestButton> createState() => _AiPullRequestButtonState();
}

class _AiPullRequestButtonState extends State<_AiPullRequestButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showingStop = widget.generating && _hovered;
    final onPressed = widget.generating
        ? widget.onCancel
        : widget.canGenerate
        ? widget.onGenerate
        : null;
    return MouseRegion(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.generating
            ? 'Stop Generating Pull Request Details'
            : 'Generate Title And Description With AI',
        child: IconButton(
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
            maxWidth: 30,
            maxHeight: 30,
          ),
          style: IconButton.styleFrom(
            minimumSize: const Size(30, 30),
            maximumSize: const Size(30, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            ),
          ),
          icon: AnimatedSwitcher(
            duration: AleraTokens.durationFast,
            child: widget.generating && !showingStop
                ? const SizedBox(
                    key: ValueKey<String>('ai-pr-loading'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AleraTokens.foregroundMuted,
                    ),
                  )
                : Icon(
                    showingStop ? AleraIcons.stop : AleraIcons.ai,
                    key: ValueKey<String>(
                      showingStop ? 'ai-pr-stop' : 'ai-pr-generate',
                    ),
                    size: 16,
                    color: showingStop
                        ? AleraTokens.error
                        : AleraTokens.foregroundMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Split primary action button matching Source Control (Fetch / Commit).
///
/// Main segment runs the selected create action; the chevron opens a menu with
/// [Create Pull Request] and [Draft Pull Request].
class _CreatePullRequestButton extends StatelessWidget {
  const _CreatePullRequestButton({
    required this.action,
    required this.busy,
    required this.enabled,
    required this.onPressed,
    required this.onSelected,
  });

  final PullRequestCreateAction action;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;
  final ValueChanged<PullRequestCreateAction> onSelected;

  static const double _height = 28;

  String get _label => switch (action) {
    PullRequestCreateAction.publish => 'Create Pull Request',
    PullRequestCreateAction.draft => 'Draft Pull Request',
  };

  IconData get _icon => switch (action) {
    PullRequestCreateAction.publish => AleraIcons.gitPullRequest,
    PullRequestCreateAction.draft => AleraIcons.edit,
  };

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AleraTokens.onAccent);
    final cursor = busy ? SystemMouseCursors.basic : SystemMouseCursors.click;
    return MouseRegion(
      cursor: cursor,
      child: Opacity(
        opacity: enabled || !busy ? 1 : 0.38,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Material(
            color: AleraTokens.accent,
            child: SizedBox(
              height: _height,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: InkWell(
                      mouseCursor: enabled
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.basic,
                      onTap: enabled ? onPressed : null,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (busy)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AleraTokens.onAccent,
                                ),
                              )
                            else
                              Icon(
                                _icon,
                                size: 15,
                                color: AleraTokens.onAccent,
                              ),
                            const SizedBox(width: AleraTokens.space8),
                            Flexible(
                              child: Text(
                                _label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textStyle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 18,
                    color: AleraTokens.onAccent.withValues(alpha: 0.18),
                  ),
                  Tooltip(
                    message: 'Create Options',
                    child: Builder(
                      builder: (context) {
                        return InkWell(
                          mouseCursor: cursor,
                          onTap: busy
                              ? null
                              : () => unawaited(_openMenu(context)),
                          child: const SizedBox(
                            width: 34,
                            height: _height,
                            child: Icon(
                              AleraIcons.chevronDown,
                              size: 17,
                              color: AleraTokens.onAccent,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    final selected = await showMenu<PullRequestCreateAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: AleraTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        side: const BorderSide(color: AleraTokens.border),
      ),
      items: <PopupMenuEntry<PullRequestCreateAction>>[
        AleraDropdownEntry<PullRequestCreateAction>(
          value: PullRequestCreateAction.publish,
          label: 'Create Pull Request',
          selected: action == PullRequestCreateAction.publish,
          leading: const Icon(AleraIcons.gitPullRequest, size: 16),
        ),
        AleraDropdownEntry<PullRequestCreateAction>(
          value: PullRequestCreateAction.draft,
          label: 'Draft Pull Request',
          selected: action == PullRequestCreateAction.draft,
          leading: const Icon(AleraIcons.edit, size: 16),
        ),
      ],
    );
    if (selected != null) {
      onSelected(selected);
    }
  }
}
