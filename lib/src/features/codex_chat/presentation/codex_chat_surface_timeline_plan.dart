part of 'codex_chat_surface.dart';

class const _CodexPlanViewScope({
  required final void Function(
    CodexTimelineCell cell,
    BuildContext sourceContext,
  )
  onMaximize,
  required final String? flyingPlanId,
  required final String? latestPlanId,
  required final Set<String> overflowingPreviewIds,
  required final void Function(String planId, {required bool overflowing})
  onPreviewOverflowChanged,
  required super.child,
}) extends InheritedWidget {
  static _CodexPlanViewScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CodexPlanViewScope>();

  @override
  bool updateShouldNotify(_CodexPlanViewScope oldWidget) =>
      onMaximize != oldWidget.onMaximize ||
      flyingPlanId != oldWidget.flyingPlanId ||
      latestPlanId != oldWidget.latestPlanId ||
      overflowingPreviewIds != oldWidget.overflowingPreviewIds;
}

class const _CodexPlanCell({
  required final CodexTimelineCell cell,
  final bool maximized = false,
  final VoidCallback? onRestore,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final planScope = _CodexPlanViewScope.maybeOf(context);
    final hidden = !maximized && planScope?.flyingPlanId == cell.id;
    final latestPlanId = planScope?.latestPlanId;
    final previous = latestPlanId != null && latestPlanId != cell.id;
    final raw = cell.markdownText ?? '';
    final text = cell.renderedMarkdownText ?? raw;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space24,
        AleraTokens.space12,
        AleraTokens.space24,
        AleraTokens.space24,
      ),
      child: _CodexMarkdownText(text: text),
    );
    return IgnorePointer(
      ignoring: hidden,
      child: Opacity(
        opacity: hidden ? 0 : 1,
        child: Container(
          key: ValueKey<String>(
            maximized
                ? 'codex-plan-card-maximized'
                : 'codex-plan-card-${cell.id}',
          ),
          margin: maximized
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(vertical: AleraTokens.space4),
          clipBehavior: .antiAlias,
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            border: Border.all(color: AleraTokens.border),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              _CodexPlanHeader(
                title: previous
                    ? 'Previous Plan'
                    : cell.isStreaming
                    ? 'Writing Plan'
                    : 'Plan',
                loading: cell.isStreaming,
                compact: (previous && !maximized) || text.trim().isEmpty,
                maximized: maximized,
                onDownload: raw.trim().isEmpty
                    ? null
                    : () => _downloadCodexPlan(context, raw),
                onCopy: raw.trim().isEmpty
                    ? null
                    : () => _copyCodexText(context, raw, 'Plan copied'),
                onToggleSize: maximized
                    ? onRestore
                    : () => planScope?.onMaximize(cell, context),
              ),
              if ((maximized || !previous) && text.trim().isNotEmpty)
                if (maximized)
                  Expanded(child: SingleChildScrollView(child: content))
                else
                  _CodexPlanPreview(
                    key: ValueKey<String>('codex-plan-preview-${cell.id}'),
                    initiallyOverflowing:
                        planScope?.overflowingPreviewIds.contains(cell.id) ==
                        true,
                    preserveOverflow: cell.isStreaming,
                    onOverflowChanged: (overflowing) =>
                        planScope?.onPreviewOverflowChanged(
                          cell.id,
                          overflowing: overflowing,
                        ),
                    content: content,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _CodexPlanPreview({
  super.key,
  required final bool initiallyOverflowing,
  required final bool preserveOverflow,
  required final ValueChanged<bool> onOverflowChanged,
  required final Widget content,
}) extends StatefulWidget {
  @override
  State<_CodexPlanPreview> createState() => _CodexPlanPreviewState();
}

class _CodexPlanPreviewState extends State<_CodexPlanPreview> {
  final ScrollController _controller = ScrollController();
  late bool _overflowing = widget.initiallyOverflowing;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleOverflowCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final overflowing = _controller.position.maxScrollExtent > 0;
      if (!overflowing && widget.preserveOverflow && _overflowing) return;
      if (overflowing != _overflowing) {
        setState(() => _overflowing = overflowing);
        widget.onOverflowChanged(overflowing);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowCheck();
    return ConstrainedBox(
      key: const ValueKey<String>('codex-plan-preview'),
      constraints: const BoxConstraints(
        maxHeight: AleraTokens.codexPlanPreviewMaxHeight,
      ),
      child: Stack(
        children: <Widget>[
          ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              child: widget.content,
            ),
          ),
          if (_overflowing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: AleraTokens.codexPlanPreviewFadeHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey<String>('codex-plan-preview-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        AleraTokens.surface.withValues(alpha: 0),
                        AleraTokens.surface.withValues(alpha: 0.08),
                        AleraTokens.surface.withValues(alpha: 0.3),
                        AleraTokens.surface.withValues(alpha: 0.68),
                        AleraTokens.surface,
                      ],
                      stops: <double>[0, 0.25, 0.5, 0.75, 1],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class const _CodexPlanHeader({
  required final String title,
  required final bool loading,
  required final bool compact,
  required final bool maximized,
  required final VoidCallback? onDownload,
  required final VoidCallback? onCopy,
  required final VoidCallback? onToggleSize,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AleraTokens.space16,
      AleraTokens.space12,
      AleraTokens.space12,
      compact ? AleraTokens.space12 : AleraTokens.space8,
    ),
    child: Row(
      children: <Widget>[
        const Icon(
          AleraIcons.plan,
          size: AleraTokens.iconXl,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space8),
        if (loading)
          _CodexShimmerText(
            key: const ValueKey<String>('codex-plan-writing-indicator'),
            text: title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
              fontWeight: .w500,
            ),
          )
        else
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
              fontWeight: .w500,
            ),
          ),
        const Spacer(),
        AleraIconButton(
          tooltip: 'Download Plan',
          icon: AleraIcons.download,
          onPressed: onDownload,
        ),
        AleraIconButton(
          tooltip: 'Copy Plan',
          icon: AleraIcons.copy,
          onPressed: onCopy,
        ),
        AleraIconButton(
          tooltip: maximized ? 'Restore Plan' : 'Maximize Plan',
          icon: maximized ? AleraIcons.minimize : AleraIcons.maximize,
          onPressed: onToggleSize,
        ),
      ],
    ),
  );
}

class const _CodexPlanFlight({
  required final CodexTimelineCell plan,
  required final AnimationController animation,
  required final GlobalKey<SelectionAreaState> selectionAreaKey,
  required final Rect sourceRect,
  required final Rect? Function() currentSourceRect,
  required final VoidCallback onRestore,
}) extends StatefulWidget {
  @override
  State<_CodexPlanFlight> createState() => _CodexPlanFlightState();
}

class _CodexPlanFlightState extends State<_CodexPlanFlight> {
  late CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.fastOutSlowIn,
    );
  }

  @override
  void didUpdateWidget(_CodexPlanFlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    _curved.dispose();
    _curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.fastOutSlowIn,
    );
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final destinationRect = Rect.fromLTWH(
            AleraTokens.space24,
            AleraTokens.space16,
            math.max(
              AleraTokens.dividerExtent,
              constraints.maxWidth - AleraTokens.space48,
            ),
            math.max(
              AleraTokens.dividerExtent,
              constraints.maxHeight - AleraTokens.space16 - AleraTokens.space8,
            ),
          );
          return Stack(
            fit: .expand,
            children: <Widget>[
              FadeTransition(
                opacity: _curved,
                child: const RepaintBoundary(
                  child: ColoredBox(color: AleraTokens.bg),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: destinationRect.width,
                height: destinationRect.height,
                child: AnimatedBuilder(
                  animation: _curved,
                  child: RepaintBoundary(
                    child: SelectionArea(
                      key: widget.selectionAreaKey,
                      child: _CodexPlanCell(
                        cell: widget.plan,
                        maximized: true,
                        onRestore: widget.onRestore,
                      ),
                    ),
                  ),
                  builder: (context, child) {
                    final flightSource =
                        widget.animation.status == AnimationStatus.reverse
                        ? widget.currentSourceRect() ?? widget.sourceRect
                        : widget.sourceRect;
                    final rect = MaterialRectArcTween(
                      begin: flightSource,
                      end: destinationRect,
                    ).lerp(_curved.value);
                    final scaleX = rect.width / destinationRect.width;
                    final scaleY = rect.height / destinationRect.height;
                    return Transform.translate(
                      offset: rect.topLeft,
                      child: Transform.scale(
                        alignment: Alignment.topLeft,
                        scaleX: scaleX,
                        scaleY: scaleY,
                        child: IgnorePointer(
                          ignoring: !widget.animation.isCompleted,
                          child: child,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _downloadCodexPlan(BuildContext context, String markdown) async {
  try {
    final location = await getSaveLocation(
      suggestedName: 'plan.md',
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'Markdown', extensions: <String>['md']),
      ],
    );
    if (location == null) return;
    await File(location.path).writeAsString(markdown, flush: true);
    if (context.mounted) {
      AleraToast.show(context, message: 'Plan downloaded', tone: .success);
    }
  } catch (error) {
    if (context.mounted) {
      AleraToast.show(
        context,
        message: 'Could not download the plan: $error',
        tone: .error,
      );
    }
  }
}
