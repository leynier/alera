part of 'welcome_dashboard.dart';

class _HomeComposerReady extends StatelessWidget {
  const _HomeComposerReady({
    required this.heading,
    required this.promptController,
    required this.promptFocusNode,
    required this.profile,
    required this.fieldsReady,
    required this.onSend,
    required this.onPaste,
    required this.onPickProfile,
    required this.hostLabel,
    required this.hostIsLocal,
    required this.onPickHost,
    required this.parentLabel,
    required this.showParent,
    required this.onPickParent,
    required this.locationLabel,
    required this.canChangeLocation,
    required this.locationIsWorktree,
    required this.onPickLocation,
    required this.enrollmentNotice,
    required this.messages,
  });

  final Widget heading;
  final TextEditingController promptController;
  final FocusNode promptFocusNode;
  final AgentProfile profile;
  final bool fieldsReady;
  final VoidCallback onSend;
  final Future<bool> Function() onPaste;
  final Future<void> Function(BuildContext context) onPickProfile;
  final String hostLabel;
  final bool hostIsLocal;
  final Future<void> Function(BuildContext context) onPickHost;
  final String parentLabel;
  final bool showParent;
  final Future<void> Function(BuildContext context) onPickParent;
  final String locationLabel;
  final bool canChangeLocation;
  final bool locationIsWorktree;
  final Future<void> Function(BuildContext context) onPickLocation;
  final Widget? enrollmentNotice;
  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        heading,
        const SizedBox(height: AleraTokens.space24),
        _HomeComposerCard(
          promptController: promptController,
          promptFocusNode: promptFocusNode,
          profile: profile,
          fieldsReady: fieldsReady,
          onSend: onSend,
          onPaste: onPaste,
          onPickProfile: onPickProfile,
          hostLabel: hostLabel,
          hostIsLocal: hostIsLocal,
          onPickHost: onPickHost,
          parentLabel: parentLabel,
          showParent: showParent,
          onPickParent: onPickParent,
          locationLabel: locationLabel,
          canChangeLocation: canChangeLocation,
          locationIsWorktree: locationIsWorktree,
          onPickLocation: onPickLocation,
        ),
        if (enrollmentNotice != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          enrollmentNotice!,
        ],
        for (final message in messages) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Text(
            message,
            textAlign: .center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.error),
          ),
        ],
      ],
    );
  }
}

class _HomeComposerCard extends StatefulWidget {
  const _HomeComposerCard({
    required this.promptController,
    required this.promptFocusNode,
    required this.profile,
    required this.fieldsReady,
    required this.onSend,
    required this.onPaste,
    required this.onPickProfile,
    required this.hostLabel,
    required this.hostIsLocal,
    required this.onPickHost,
    required this.parentLabel,
    required this.showParent,
    required this.onPickParent,
    required this.locationLabel,
    required this.canChangeLocation,
    required this.locationIsWorktree,
    required this.onPickLocation,
  });

  final TextEditingController promptController;
  final FocusNode promptFocusNode;
  final AgentProfile profile;
  final bool fieldsReady;
  final VoidCallback onSend;
  final Future<bool> Function() onPaste;
  final Future<void> Function(BuildContext context) onPickProfile;
  final String hostLabel;
  final bool hostIsLocal;
  final Future<void> Function(BuildContext context) onPickHost;
  final String parentLabel;
  final bool showParent;
  final Future<void> Function(BuildContext context) onPickParent;
  final String locationLabel;
  final bool canChangeLocation;
  final bool locationIsWorktree;
  final Future<void> Function(BuildContext context) onPickLocation;

  @override
  State<_HomeComposerCard> createState() => _HomeComposerCardState();
}

class _HomeComposerCardState extends State<_HomeComposerCard> {
  @override
  void initState() {
    super.initState();
    widget.promptController.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.promptFocusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(_HomeComposerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.promptController != widget.promptController) {
      oldWidget.promptController.removeListener(_rebuild);
      widget.promptController.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.promptController.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canSend =>
      widget.fieldsReady && widget.promptController.text.trim().isNotEmpty;

  void _send() {
    if (_canSend) {
      widget.onSend();
    }
  }

  void _insertLineBreak() {
    final value = widget.promptController.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    widget.promptController.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: .collapsed(offset: start + 1),
      composing: .empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
          border: Border.all(color: AleraTokens.border),
        ),
        child: AiDictationTarget(
          controller: widget.promptController,
          focusNode: widget.promptFocusNode,
          initialPrompt: 'The user is describing a software task for Alera.',
          builder: (context, targetId) {
            return Column(
              mainAxisSize: .min,
              children: <Widget>[
                Actions(
                  actions: <Type, Action<Intent>>{
                    PasteTextIntent: AleraClipboardPasteAction(widget.onPaste),
                  },
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(.enter, includeRepeats: false):
                          _send,
                      const SingleActivator(.enter, shift: true):
                          _insertLineBreak,
                      const SingleActivator(
                        .enter,
                        control: true,
                        includeRepeats: false,
                      ): _send,
                      const SingleActivator(
                        .enter,
                        meta: true,
                        includeRepeats: false,
                      ): _send,
                    },
                    child: TextField(
                      key: const ValueKey<String>('home-composer-prompt'),
                      controller: widget.promptController,
                      focusNode: widget.promptFocusNode,
                      minLines: 3,
                      maxLines: 8,
                      textInputAction: .newline,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: 'Describe what the agent should build or paste an image',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                        filled: true,
                        fillColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        contentPadding: const EdgeInsets.fromLTRB(
                          AleraTokens.space12,
                          AleraTokens.space16,
                          AleraTokens.space12,
                          AleraTokens.space8,
                        ),
                        border: .none,
                        enabledBorder: .none,
                        focusedBorder: .none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AleraTokens.space8,
                    0,
                    AleraTokens.space8,
                    AleraTokens.space8,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: AleraHorizontalScrollView(
                          child: Row(
                            children: <Widget>[
                              _HomeComposerChip(
                                key: const ValueKey<String>(
                                  'home-composer-profile',
                                ),
                                label: widget.profile.name,
                                leading: AgentIdentityIcon(
                                  agentType:
                                      AgentType.tryParse(
                                        widget.profile.agentType,
                                      ) ??
                                      .codex,
                                  size: AleraTokens.iconMd,
                                  showTooltip: false,
                                ),
                                onPressed: widget.onPickProfile,
                              ),
                            ],
                          ),
                        ),
                      ),
                      AiDictationControl(
                        key: const ValueKey<String>('home-composer-dictation'),
                        targetId: targetId,
                      ),
                      const SizedBox(width: AleraTokens.space4),
                      AleraIconButton(
                        key: const ValueKey<String>('home-composer-send'),
                        tooltip: 'Create and Start Agent',
                        icon: AleraIcons.arrowUp,
                        iconColor: _canSend
                            ? AleraTokens.onAccent
                            : AleraTokens.foregroundFaint,
                        backgroundColor: _canSend
                            ? AleraTokens.accent
                            : AleraTokens.surface,
                        borderRadius: AleraTokens.radiusPill,
                        minSize: AleraTokens.space32,
                        onPressed: _canSend ? _send : null,
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AleraTokens.border)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space8,
                      vertical: AleraTokens.space8,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: AleraHorizontalScrollView(
                            child: Row(
                              children: <Widget>[
                                _HomeComposerChip(
                                  key: const ValueKey<String>(
                                    'home-composer-host',
                                  ),
                                  label: widget.hostLabel,
                                  leading: Icon(
                                    widget.hostIsLocal
                                        ? AleraIcons.workspaceMain
                                        : AleraIcons.host,
                                    size: AleraTokens.iconMd,
                                    color: AleraTokens.foregroundMuted,
                                  ),
                                  onPressed: widget.onPickHost,
                                ),
                                if (widget.showParent) ...<Widget>[
                                  const SizedBox(width: AleraTokens.space8),
                                  _HomeComposerChip(
                                    key: const ValueKey<String>(
                                      'home-composer-parent',
                                    ),
                                    label: widget.parentLabel,
                                    onPressed: widget.onPickParent,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: AleraTokens.space8),
                        if (widget.canChangeLocation)
                          _HomeComposerChip(
                            key: const ValueKey<String>(
                              'home-composer-location',
                            ),
                            label: widget.locationLabel,
                            leading: widget.locationIsWorktree
                                ? const Icon(
                                    AleraIcons.gitBranch,
                                    size: AleraTokens.iconMd,
                                    color: AleraTokens.foregroundMuted,
                                  )
                                : null,
                            onPressed: widget.onPickLocation,
                          )
                        else
                          Text(
                            widget.locationLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeComposerChip extends StatelessWidget {
  const _HomeComposerChip({
    super.key,
    required this.label,
    this.leading,
    this.onPressed,
  });

  final String label;
  final Widget? leading;
  final void Function(BuildContext context)? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final pressed = onPressed;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: AleraTokens.foregroundMuted,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        tapTargetSize: .shrinkWrap,
        visualDensity: .compact,
      ),
      onPressed: pressed == null ? null : () => pressed(context),
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AleraTokens.space4),
          ],
          Text(label, style: style),
          if (onPressed != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            const Icon(
              AleraIcons.chevronDown,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundMuted,
            ),
          ],
        ],
      ),
    );
  }
}

extension _WelcomeDashboardClipboard on _WelcomeDashboardState {
  Future<bool> _pastePromptClipboard() async {
    String? clipboardText;
    try {
      clipboardText = await _clipboard.readText();
    } catch (_) {
      // Image-only clipboards can reject text reads on some platforms.
    }
    if (clipboardText != null && clipboardText.isNotEmpty) {
      return false;
    }
    try {
      final imagePath = await _clipboard.saveImageAsTempFile();
      if (!mounted || imagePath == null || imagePath.isEmpty) {
        return false;
      }
      final value = _promptController.value;
      final selection = value.selection;
      final safeSelection =
          selection.isValid &&
              selection.start <= value.text.length &&
              selection.end <= value.text.length
          ? selection
          : TextSelection.collapsed(offset: value.text.length);
      _promptController.value = value.replaced(
        safeSelection,
        sanitizeTerminalImagePastePath(imagePath),
      );
      _update(() => _error = null);
      return true;
    } catch (_) {
      if (mounted) {
        _update(() => _error = 'Could not paste clipboard image.');
      }
      return true;
    }
  }
}
