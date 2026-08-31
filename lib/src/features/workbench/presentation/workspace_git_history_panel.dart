part of 'workspace_git_diff_panel.dart';

enum _GitHistoryPanelStatus { idle, loading, ready, error }

class const _GitHistoryPanelLoadState._({
  required final _GitHistoryPanelStatus status,
  final GitHistoryResult? result,
  final String? error,
  final bool loading = false,
}) {
  const new idle() : this._(status: .idle);

  const new loading() : this._(status: .loading, loading: true);

  const new ready({required GitHistoryResult result, bool loading = false})
    : this._(status: .ready, result: result, loading: loading);

  const new error({
    required String error,
    GitHistoryResult? result,
    bool loading = false,
  }) : this._(status: .error, result: result, error: error, loading: loading);
}

class const _GitHistoryPanel({
  required final _GitHistoryPanelLoadState state,
  required final bool collapsed,
  required final VoidCallback onToggle,
  required final Future<void> Function() onRefresh,
  required final Future<List<GitCommitChangeEntry>> Function(
    GitHistoryItem item,
  )
  onLoadCommitFiles,
  required final Future<void> Function(GitHistoryItem item) onOpenCommit,
  required final Future<void> Function(
    GitHistoryItem item,
    GitCommitChangeEntry entry,
  )
  onOpenCommitFile,
  required final Future<void> Function(String text, String label)
  onCopyCommitText,
}) extends StatefulWidget {
  @override
  State<_GitHistoryPanel> createState() => _GitHistoryPanelState();
}

class _GitHistoryPanelState extends State<_GitHistoryPanel> {
  static const double _defaultHeight = 256;
  static const double _minHeight = 96;
  static const double _maxHeight = 520;

  final Set<String> _expandedCommitIds = <String>{};
  final Map<String, _CommitFilesState> _filesByCommit =
      <String, _CommitFilesState>{};
  double _height = _defaultHeight;

  @override
  void didUpdateWidget(covariant _GitHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.result != widget.state.result) {
      final currentCommitIds =
          widget.state.result?.items.map((item) => item.id).toSet() ??
          <String>{};
      _expandedCommitIds.retainAll(currentCommitIds);
      _filesByCommit.removeWhere(
        (commitId, _) => !currentCommitIds.contains(commitId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.state.result;
    final count = result?.items.length ?? 0;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.surfaceVariant),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          if (widget.collapsed)
            const Divider(height: 1, color: AleraTokens.borderSubtle)
          else
            _HistoryResizeHandle(onResize: _resize),
          DecoratedBox(
            decoration: const BoxDecoration(color: AleraTokens.surface),
            child: SizedBox(
              height: AleraTokens.sidebarHeaderHeight,
              // The whole strip toggles the section, so the hover tint runs
              // edge to edge and stays square: a rounded inset block would
              // read as a button instead of a section row.
              child: HoverContainer(
                onTap: widget.onToggle,
                hoverColor: AleraTokens.surfaceVariant,
                borderRadius: 0,
                padding: const .symmetric(horizontal: AleraTokens.space8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _HistoryHeaderLabel(
                        collapsed: widget.collapsed,
                        count: count,
                        hasMore: result?.hasMore ?? false,
                        showCount: result != null,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    _RefreshCommitsButton(
                      loading: widget.state.loading,
                      onPressed: () => unawaited(widget.onRefresh()),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!widget.collapsed)
            SizedBox(height: _height, child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final state = widget.state;
    final result = state.result;
    if (state.status == _GitHistoryPanelStatus.error && result == null) {
      return _HistoryMessage(message: state.error ?? 'Could not load commits');
    }
    if (result == null) {
      return const _HistoryLoadingMessage();
    }
    final viewModels = buildGitHistoryViewModels(result);
    if (viewModels.isEmpty) {
      return const _HistoryMessage(message: 'No commits yet');
    }
    return Stack(
      children: <Widget>[
        ListView.builder(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          itemCount: viewModels.length,
          itemBuilder: (context, index) {
            final viewModel = viewModels[index];
            final item = viewModel.historyItem;
            final boundary =
                viewModel.kind == GitHistoryItemViewModelKind.incomingChanges ||
                viewModel.kind == GitHistoryItemViewModelKind.outgoingChanges;
            final expanded = _expandedCommitIds.contains(item.id);
            return Column(
              mainAxisSize: .min,
              children: <Widget>[
                _GitHistoryCommitRow(
                  viewModel: viewModel,
                  expanded: expanded,
                  onTap: boundary ? null : () => _toggleCommit(item),
                  onOpenActions: boundary
                      ? null
                      : (context) => _openActions(context, item),
                ),
                if (expanded)
                  _CommitFiles(
                    state:
                        _filesByCommit[item.id] ??
                        const _CommitFilesState.loading(),
                    author: item.author,
                    timestamp: item.timestamp,
                    onOpenAll: () => unawaited(widget.onOpenCommit(item)),
                    onOpenFile: (entry) =>
                        unawaited(widget.onOpenCommitFile(item, entry)),
                  ),
              ],
            );
          },
        ),
        if (state.loading)
          const Positioned(
            top: AleraTokens.space8,
            right: AleraTokens.space8,
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  void _resize(double delta) {
    setState(() {
      _height = (_height - delta).clamp(_minHeight, _maxHeight);
    });
  }

  void _toggleCommit(GitHistoryItem item) {
    final expanding = !_expandedCommitIds.contains(item.id);
    setState(() {
      if (expanding) {
        _expandedCommitIds.add(item.id);
        _filesByCommit[item.id] = const _CommitFilesState.loading();
      } else {
        _expandedCommitIds.remove(item.id);
      }
    });
    if (!expanding) {
      return;
    }
    widget
        .onLoadCommitFiles(item)
        .then(
          (entries) {
            if (!mounted || !_expandedCommitIds.contains(item.id)) {
              return;
            }
            setState(() {
              _filesByCommit[item.id] = _CommitFilesState.ready(
                entries: entries,
              );
            });
          },
          onError: (Object error) {
            if (!mounted || !_expandedCommitIds.contains(item.id)) {
              return;
            }
            setState(() {
              _filesByCommit[item.id] = _CommitFilesState.error(
                error: error.toString(),
              );
            });
          },
        );
  }

  Future<void> _openActions(BuildContext context, GitHistoryItem item) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (renderBox == null || overlay is! RenderBox) {
      return;
    }
    final topLeft = renderBox.localToGlobal(.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final action = await showMenu<_CommitAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<_CommitAction>>[
        AleraDropdownEntry<_CommitAction>(
          value: .copyHash,
          label: 'Copy Commit Hash',
          leading: Icon(AleraIcons.gitBranch, size: 16),
        ),
        AleraDropdownEntry<_CommitAction>(
          value: .copyMessage,
          label: 'Copy Commit Message',
          leading: Icon(AleraIcons.copy, size: 16),
        ),
      ],
    );
    if (action == null) {
      return;
    }
    switch (action) {
      case _CommitAction.copyHash:
        await widget.onCopyCommitText(item.id, 'Commit Hash');
      case _CommitAction.copyMessage:
        await widget.onCopyCommitText(
          item.message.trim().isEmpty ? item.subject : item.message,
          'Commit Message',
        );
    }
  }
}

class const _HistoryHeaderLabel({
  required final bool collapsed,
  required final int count,
  required final bool hasMore,
  required final bool showCount,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Icon(
          collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
          size: 14,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space6),
        Text(
          'Commits'.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
            letterSpacing: 0.6,
            fontWeight: .w700,
          ),
        ),
        if (showCount) ...<Widget>[
          const SizedBox(width: AleraTokens.space6),
          Text(
            hasMore ? '$count+' : '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ],
      ],
    );
  }
}

class const _RefreshCommitsButton({
  required final bool loading,
  required final VoidCallback onPressed,
}) extends StatefulWidget {
  @override
  State<_RefreshCommitsButton> createState() => _RefreshCommitsButtonState();
}

class _RefreshCommitsButtonState extends State<_RefreshCommitsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.loading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RefreshCommitsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading) {
      if (widget.loading) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh Commits',
      onPressed: widget.loading ? null : widget.onPressed,
      icon: RotationTransition(
        turns: _controller,
        child: const Icon(
          AleraIcons.refresh,
          size: 15,
          color: AleraTokens.foregroundMuted,
        ),
      ),
      visualDensity: .compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      style: IconButton.styleFrom(
        backgroundColor: AleraTokens.surfaceVariant,
        side: const BorderSide(color: AleraTokens.borderSubtle),
        minimumSize: const Size(30, 30),
        maximumSize: const Size(30, 30),
        tapTargetSize: .shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
      ),
    );
  }
}

enum _CommitAction { copyHash, copyMessage }

class const _HistoryResizeHandle({required final ValueChanged<double> onResize})
    extends StatefulWidget {
  @override
  State<_HistoryResizeHandle> createState() => _HistoryResizeHandleState();
}

class _HistoryResizeHandleState extends State<_HistoryResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final lineColor = _dragging
        ? AleraTokens.accent
        : (_hovered ? AleraTokens.foregroundFaint : AleraTokens.borderSubtle);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: .opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (details) => widget.onResize(details.delta.dy),
        onVerticalDragEnd: (_) => _stopDragging(),
        onVerticalDragCancel: _stopDragging,
        child: SizedBox(
          height: AleraTokens.space6,
          child: Stack(
            fit: .expand,
            children: <Widget>[
              const ColoredBox(color: AleraTokens.surface),
              Positioned(
                left: 0,
                right: 0,
                top: AleraTokens.space2,
                bottom: AleraTokens.space2,
                child: AnimatedContainer(
                  duration: AleraTokens.durationFast,
                  color: lineColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    setState(() => _dragging = false);
  }
}
