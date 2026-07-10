part of 'workspace_git_diff_panel.dart';

enum _GitHistoryPanelStatus { idle, loading, ready, error }

class _GitHistoryPanelLoadState {
  const _GitHistoryPanelLoadState._({
    required this.status,
    this.result,
    this.error,
    this.loading = false,
  });

  const _GitHistoryPanelLoadState.idle()
    : this._(status: _GitHistoryPanelStatus.idle);

  const _GitHistoryPanelLoadState.loading()
    : this._(status: _GitHistoryPanelStatus.loading, loading: true);

  const _GitHistoryPanelLoadState.ready({
    required GitHistoryResult result,
    bool loading = false,
  }) : this._(
         status: _GitHistoryPanelStatus.ready,
         result: result,
         loading: loading,
       );

  const _GitHistoryPanelLoadState.error({
    required String error,
    GitHistoryResult? result,
    bool loading = false,
  }) : this._(
         status: _GitHistoryPanelStatus.error,
         result: result,
         error: error,
         loading: loading,
       );

  final _GitHistoryPanelStatus status;
  final GitHistoryResult? result;
  final String? error;
  final bool loading;
}

class _GitHistoryPanel extends StatefulWidget {
  const _GitHistoryPanel({
    required this.state,
    required this.collapsed,
    required this.onToggle,
    required this.onRefresh,
    required this.onLoadCommitFiles,
    required this.onOpenCommit,
    required this.onOpenCommitFile,
    required this.onCopyCommitText,
  });

  final _GitHistoryPanelLoadState state;
  final bool collapsed;
  final VoidCallback onToggle;
  final Future<void> Function() onRefresh;
  final Future<List<GitCommitChangeEntry>> Function(GitHistoryItem item)
  onLoadCommitFiles;
  final Future<void> Function(GitHistoryItem item) onOpenCommit;
  final Future<void> Function(GitHistoryItem item, GitCommitChangeEntry entry)
  onOpenCommitFile;
  final Future<void> Function(String text, String label) onCopyCommitText;

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
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!widget.collapsed) _ResizeHandle(onResize: _resize),
          DecoratedBox(
            decoration: const BoxDecoration(color: AleraTokens.surface),
            child: SizedBox(
              height: AleraTokens.sidebarHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: widget.onToggle,
                      icon: Icon(
                        widget.collapsed
                            ? AleraIcons.chevronRight
                            : AleraIcons.chevronDown,
                        size: 15,
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Commits',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AleraTokens.foregroundMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (result != null) ...<Widget>[
                            const SizedBox(width: AleraTokens.space6),
                            Text(
                              result.hasMore ? '$count+' : '$count',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundFaint,
                                  ),
                            ),
                          ],
                        ],
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AleraTokens.foregroundMuted,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space8,
                          vertical: AleraTokens.space4,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AleraTokens.radiusMd,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
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
      return _HistoryMessage(message: state.error ?? 'Could Not Load Commits');
    }
    if (result == null) {
      return const _HistoryLoadingMessage();
    }
    final viewModels = buildGitHistoryViewModels(result);
    if (viewModels.isEmpty) {
      return const _HistoryMessage(message: 'No Commits Yet');
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
              mainAxisSize: MainAxisSize.min,
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
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = renderBox.localToGlobal(
      renderBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final action = await showMenu<_CommitAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<_CommitAction>>[
        AleraDropdownEntry<_CommitAction>(
          value: _CommitAction.copyHash,
          label: 'Copy Commit Hash',
          leading: Icon(AleraIcons.gitBranch, size: 16),
        ),
        AleraDropdownEntry<_CommitAction>(
          value: _CommitAction.copyMessage,
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

class _RefreshCommitsButton extends StatefulWidget {
  const _RefreshCommitsButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

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
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      style: IconButton.styleFrom(
        backgroundColor: AleraTokens.surfaceVariant,
        side: const BorderSide(color: AleraTokens.borderSubtle),
        minimumSize: const Size(30, 30),
        maximumSize: const Size(30, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
      ),
    );
  }
}

enum _CommitAction { copyHash, copyMessage }

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onResize});

  final ValueChanged<double> onResize;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (details) => onResize(details.delta.dy),
        child: const SizedBox(height: AleraTokens.space4),
      ),
    );
  }
}

class _GitHistoryCommitRow extends StatelessWidget {
  const _GitHistoryCommitRow({
    required this.viewModel,
    required this.expanded,
    required this.onTap,
    required this.onOpenActions,
  });

  final GitHistoryItemViewModel viewModel;
  final bool expanded;
  final VoidCallback? onTap;
  final void Function(BuildContext context)? onOpenActions;

  @override
  Widget build(BuildContext context) {
    final item = viewModel.historyItem;
    final boundary =
        viewModel.kind == GitHistoryItemViewModelKind.incomingChanges ||
        viewModel.kind == GitHistoryItemViewModelKind.outgoingChanges;
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: InkWell(
        onTap: onTap,
        mouseCursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AleraTokens.space8,
              right: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                _GitHistoryGraph(viewModel: viewModel),
                const SizedBox(width: AleraTokens.space4),
                if (!boundary)
                  Icon(
                    expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                    size: 14,
                    color: AleraTokens.foregroundFaint,
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: AleraTokens.space4),
                Expanded(
                  child: Text(
                    item.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: boundary
                          ? AleraTokens.foregroundMuted
                          : AleraTokens.foreground,
                    ),
                  ),
                ),
                for (final itemRef in item.references.take(2)) ...<Widget>[
                  const SizedBox(width: AleraTokens.space4),
                  _GitRefBadge(itemRef: itemRef),
                ],
                if (item.references.length > 2) ...<Widget>[
                  const SizedBox(width: AleraTokens.space4),
                  Text(
                    '+${item.references.length - 2}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                ],
                if (onOpenActions != null)
                  Builder(
                    builder: (context) => AleraIconButton(
                      tooltip: 'Commit Actions',
                      icon: AleraIcons.more,
                      onPressed: () => onOpenActions!(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GitRefBadge extends StatelessWidget {
  const _GitRefBadge({required this.itemRef});

  final GitHistoryItemRef itemRef;

  @override
  Widget build(BuildContext context) {
    final color = _graphColor(itemRef.color);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        border: Border.all(color: color ?? AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: AleraTokens.space2,
        ),
        child: Text(
          itemRef.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color ?? AleraTokens.foregroundMuted,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

class _GitHistoryGraph extends StatelessWidget {
  const _GitHistoryGraph({required this.viewModel});

  final GitHistoryItemViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final width =
        11.0 *
        ([
              viewModel.inputSwimlanes.length,
              viewModel.outputSwimlanes.length,
              1,
            ].reduce((a, b) => a > b ? a : b) +
            1);
    return SizedBox(
      width: width,
      height: 24,
      child: CustomPaint(painter: _GitHistoryGraphPainter(viewModel)),
    );
  }
}

class _GitHistoryGraphPainter extends CustomPainter {
  const _GitHistoryGraphPainter(this.viewModel);

  static const double laneHeight = 24;
  static const double laneWidth = 11;
  static const double nodeY = laneHeight / 2;
  static const double circleRadius = 3.5;

  final GitHistoryItemViewModel viewModel;

  @override
  void paint(Canvas canvas, Size size) {
    final item = viewModel.historyItem;
    final input = viewModel.inputSwimlanes;
    final output = viewModel.outputSwimlanes;
    final inputIndex = input.indexWhere((node) => node.id == item.id);
    final circleIndex = gitHistoryItemLaneIndex(viewModel);
    final circleColor = circleIndex < output.length
        ? output[circleIndex].color
        : circleIndex < input.length
        ? input[circleIndex].color
        : gitHistoryRefColor;
    var outputIndex = 0;

    for (var index = 0; index < input.length; index += 1) {
      final color = input[index].color;
      if (input[index].id == item.id) {
        if (index != circleIndex) {
          _drawPath(
            canvas,
            color,
            Path()
              ..moveTo(laneWidth * (index + 1), 0)
              ..quadraticBezierTo(
                laneWidth * index,
                nodeY,
                laneWidth * (circleIndex + 1),
                nodeY,
              ),
          );
        } else {
          outputIndex += 1;
        }
        continue;
      }
      if (outputIndex < output.length &&
          input[index].id == output[outputIndex].id) {
        final path = Path()..moveTo(laneWidth * (index + 1), 0);
        if (index == outputIndex) {
          path.lineTo(laneWidth * (index + 1), laneHeight);
        } else {
          path
            ..lineTo(laneWidth * (index + 1), 6)
            ..quadraticBezierTo(
              laneWidth * (index + 1),
              nodeY,
              laneWidth * (outputIndex + 1),
              nodeY,
            )
            ..lineTo(laneWidth * (outputIndex + 1), laneHeight);
        }
        _drawPath(canvas, color, path);
        outputIndex += 1;
      }
    }

    for (var index = 1; index < item.parentIds.length; index += 1) {
      final parentIndex = gitHistoryMergeParentLaneIndex(
        viewModel,
        item.parentIds[index],
      );
      if (parentIndex == -1) {
        continue;
      }
      _drawPath(
        canvas,
        output[parentIndex].color,
        Path()
          ..moveTo(laneWidth * (parentIndex + 1), nodeY)
          ..lineTo(laneWidth * (circleIndex + 1), nodeY)
          ..moveTo(laneWidth * (parentIndex + 1), nodeY)
          ..quadraticBezierTo(
            laneWidth * (parentIndex + 1),
            laneHeight,
            laneWidth * (parentIndex + 1),
            laneHeight,
          ),
      );
    }

    if (inputIndex != -1) {
      _drawPath(
        canvas,
        input[inputIndex].color,
        Path()
          ..moveTo(laneWidth * (circleIndex + 1), 0)
          ..lineTo(laneWidth * (circleIndex + 1), nodeY),
      );
    }
    if (item.parentIds.isNotEmpty) {
      _drawPath(
        canvas,
        circleColor,
        Path()
          ..moveTo(laneWidth * (circleIndex + 1), nodeY)
          ..lineTo(laneWidth * (circleIndex + 1), laneHeight),
      );
    }

    _drawNode(canvas, circleIndex, circleColor);
  }

  void _drawPath(Canvas canvas, GitHistoryGraphColorId color, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _graphColor(color) ?? AleraTokens.foregroundMuted
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawNode(Canvas canvas, int circleIndex, GitHistoryGraphColorId color) {
    final center = Offset(laneWidth * (circleIndex + 1), nodeY);
    final paint = Paint()..color = _graphColor(color) ?? AleraTokens.foreground;
    final boundary =
        viewModel.kind == GitHistoryItemViewModelKind.incomingChanges ||
        viewModel.kind == GitHistoryItemViewModelKind.outgoingChanges;
    if (viewModel.kind == GitHistoryItemViewModelKind.head || boundary) {
      canvas.drawCircle(center, circleRadius + 3, paint);
      canvas.drawCircle(center, circleRadius, Paint()..color = AleraTokens.bg);
      if (boundary) {
        canvas.drawCircle(
          center,
          circleRadius + 1,
          Paint()
            ..color = paint.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      return;
    }
    if (viewModel.historyItem.parentIds.length > 1) {
      canvas.drawCircle(center, circleRadius + 1, paint);
      canvas.drawCircle(
        center,
        circleRadius - 1.5,
        Paint()..color = AleraTokens.bg,
      );
      return;
    }
    canvas.drawCircle(center, circleRadius, paint);
  }

  @override
  bool shouldRepaint(covariant _GitHistoryGraphPainter oldDelegate) {
    return oldDelegate.viewModel != viewModel;
  }
}

Color? _graphColor(GitHistoryGraphColorId? color) {
  return switch (color) {
    GitHistoryGraphColorId.ref => AleraTokens.success,
    GitHistoryGraphColorId.remoteRef => AleraTokens.info,
    GitHistoryGraphColorId.baseRef => AleraTokens.warning,
    GitHistoryGraphColorId.lane1 => AleraTokens.syntaxFunction,
    GitHistoryGraphColorId.lane2 => AleraTokens.syntaxKeyword,
    GitHistoryGraphColorId.lane3 => AleraTokens.syntaxLiteral,
    GitHistoryGraphColorId.lane4 => AleraTokens.syntaxOperator,
    GitHistoryGraphColorId.lane5 => AleraTokens.foregroundMuted,
    null => null,
  };
}

class _CommitFilesState {
  const _CommitFilesState.loading()
    : entries = const <GitCommitChangeEntry>[],
      error = null,
      loading = true;

  const _CommitFilesState.ready({required this.entries})
    : error = null,
      loading = false;

  const _CommitFilesState.error({required this.error})
    : entries = const <GitCommitChangeEntry>[],
      loading = false;

  final List<GitCommitChangeEntry> entries;
  final String? error;
  final bool loading;
}

class _CommitFiles extends StatelessWidget {
  const _CommitFiles({
    required this.state,
    required this.author,
    required this.timestamp,
    required this.onOpenAll,
    required this.onOpenFile,
  });

  final _CommitFilesState state;
  final String? author;
  final DateTime? timestamp;
  final VoidCallback onOpenAll;
  final ValueChanged<GitCommitChangeEntry> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (author != null && author!.trim().isNotEmpty) author!,
      if (timestamp != null) _formatTimestamp(timestamp!),
    ].join(' · ');
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: 40,
                right: AleraTokens.space8,
                top: AleraTokens.space4,
                bottom: AleraTokens.space2,
              ),
              child: Text(
                meta,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          if (state.loading)
            const Padding(
              padding: EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text('Loading Files...'),
            )
          else if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text(
                state.error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
              ),
            )
          else if (state.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(40, 4, 8, 6),
              child: Text('No File Changes'),
            )
          else ...<Widget>[
            for (final entry in state.entries)
              _CommitFileRow(entry: entry, onOpen: () => onOpenFile(entry)),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                onTap: onOpenAll,
                mouseCursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 5, 8, 7),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        AleraIcons.external,
                        size: 13,
                        color: AleraTokens.foregroundMuted,
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      Text(
                        'Open All Changes',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _CommitFileRow extends StatelessWidget {
  const _CommitFileRow({required this.entry, required this.onOpen});

  final GitCommitChangeEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final label = entry.oldPath == null
        ? entry.path
        : '${entry.oldPath} -> ${entry.path}';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onOpen,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 4, 8, 4),
          child: Row(
            children: <Widget>[
              AleraFileIcon(
                pathOrName: entry.path,
                kind: AleraFileIconKind.file,
                size: 14,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AleraTokens.monoStyle.copyWith(
                    color: AleraTokens.foregroundMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              _CommitStats(entry: entry),
              const SizedBox(width: AleraTokens.space6),
              _GitStatusLabel(status: entry.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitStats extends StatelessWidget {
  const _CommitStats({required this.entry});

  final GitCommitChangeEntry entry;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (entry.added case final added? when added > 0)
          Text('+$added', style: style?.copyWith(color: AleraTokens.success)),
        if (entry.removed case final removed? when removed > 0) ...<Widget>[
          const SizedBox(width: AleraTokens.space4),
          Text('-$removed', style: style?.copyWith(color: AleraTokens.error)),
        ],
      ],
    );
  }
}

class _HistoryLoadingMessage extends StatelessWidget {
  const _HistoryLoadingMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
