part of 'codex_chat_surface.dart';

class _CodexPromptOptionRow extends StatefulWidget {
  const new({
    required this.index,
    required this.label,
    required this.selected,
    required this.onTap,
    this.description,
    this.recommended = false,
  }) : other = false,
       trailing = null;

  const new other({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  }) : index = null,
       description = null,
       recommended = false,
       other = true;

  static const String otherValue = '__other__';

  final int? index;
  final String label;
  final String? description;
  final bool recommended;
  final bool selected;
  final bool other;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<_CodexPromptOptionRow> createState() => _CodexPromptOptionRowState();
}

class _CodexPromptOptionRowState extends State<_CodexPromptOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || widget.selected;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        mouseCursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusLg),
        child: AnimatedContainer(
          key: ValueKey<String>('codex-option-row-${widget.index ?? 'other'}'),
          width: .infinity,
          duration: AleraTokens.durationFast,
          margin: const EdgeInsets.only(bottom: AleraTokens.space2),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          decoration: BoxDecoration(
            color: active ? AleraTokens.accentSubtle : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AleraTokens.space32,
                height: AleraTokens.space32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: .circle,
                  border: Border.all(color: AleraTokens.border),
                ),
                child: widget.other
                    ? const Icon(
                        AleraIcons.edit,
                        size: AleraTokens.iconLg,
                        color: AleraTokens.foregroundMuted,
                      )
                    : Text(
                        '${widget.index}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AleraTokens.foregroundMuted),
                      ),
              ),
              const SizedBox(width: AleraTokens.space12),
              Expanded(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            widget.label,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: widget.other
                                      ? AleraTokens.foregroundMuted
                                      : AleraTokens.foreground,
                                  fontWeight: widget.other
                                      ? FontWeight.w400
                                      : FontWeight.w500,
                                ),
                          ),
                        ),
                        if (widget.recommended) ...<Widget>[
                          const SizedBox(width: AleraTokens.space8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AleraTokens.space8,
                              vertical: AleraTokens.space2,
                            ),
                            decoration: BoxDecoration(
                              color: AleraTokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(
                                AleraTokens.radiusPill,
                              ),
                            ),
                            child: Text(
                              'Recommended',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundMuted,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.description case final String description
                        when description.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AleraTokens.space4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AleraTokens.foregroundMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing case final Widget trailing) trailing,
              if (widget.trailing == null)
                Visibility(
                  key: ValueKey<String>(
                    'codex-option-row-arrow-space-${widget.index}',
                  ),
                  visible: active,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: const Icon(
                    AleraIcons.chevronRight,
                    key: ValueKey<String>('codex-option-row-arrow'),
                    size: AleraTokens.iconLg,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _CodexPromptInlineAnswerRow({
  required final TextEditingController controller,
  required final String hintText,
  required final String actionLabel,
  required final VoidCallback onChanged,
  required final VoidCallback? onSkip,
  required final VoidCallback? onSubmit,
  final bool obscureText = false,
}) extends StatefulWidget {
  @override
  State<_CodexPromptInlineAnswerRow> createState() =>
      _CodexPromptInlineAnswerRowState();
}

class _CodexPromptInlineAnswerRowState
    extends State<_CodexPromptInlineAnswerRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        if (hasText) widget.onSubmit?.call();
        return KeyEventResult.handled;
      },
      child: Container(
        key: const ValueKey<String>('codex-inline-answer-row'),
        constraints: const BoxConstraints(
          minHeight: AleraTokens.space32 + AleraTokens.space8,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.accentSubtle,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          border: Border.all(
            color: AleraTokens.info,
            width: AleraTokens.strokeHairline,
          ),
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.space8 +
                      AleraTokens.space32 +
                      AleraTokens.space12,
                  AleraTokens.space8,
                  AleraTokens.space8 +
                      AleraTokens.space48 +
                      AleraTokens.space24,
                  AleraTokens.space8,
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: TextField(
                    controller: widget.controller,
                    scrollController: _scrollController,
                    autofocus: true,
                    obscureText: widget.obscureText,
                    minLines: 1,
                    maxLines: widget.obscureText ? 1 : 5,
                    keyboardType: widget.obscureText
                        ? TextInputType.text
                        : TextInputType.multiline,
                    textInputAction: widget.obscureText
                        ? TextInputAction.done
                        : TextInputAction.newline,
                    onChanged: (_) => widget.onChanged(),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      isCollapsed: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: .none,
                      enabledBorder: .none,
                      focusedBorder: .none,
                      disabledBorder: .none,
                      errorBorder: .none,
                      focusedErrorBorder: .none,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: AleraTokens.space8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: AleraTokens.space32,
                    height: AleraTokens.space32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: .circle,
                      border: Border.all(color: AleraTokens.border),
                    ),
                    child: const Icon(
                      AleraIcons.edit,
                      size: AleraTokens.iconLg,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: AleraTokens.space8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox(
                    height: AleraTokens.space32,
                    child: hasText
                        ? FilledButton(
                            onPressed: widget.onSubmit,
                            style: FilledButton.styleFrom(
                              minimumSize: .zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AleraTokens.space12,
                                vertical: AleraTokens.space6,
                              ),
                              tapTargetSize: .shrinkWrap,
                              shape: const StadiumBorder(),
                            ),
                            child: Text(widget.actionLabel),
                          )
                        : _CodexSkipButton(onPressed: widget.onSkip),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _CodexSkipButton({required final VoidCallback? onPressed})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: .zero,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      tapTargetSize: .shrinkWrap,
      shape: const StadiumBorder(),
    ),
    child: const Text('Skip'),
  );
}
