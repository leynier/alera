part of 'codex_chat_surface.dart';

class _CodexPendingQuestionQueue extends StatefulWidget {
  const _CodexPendingQuestionQueue({
    super.key,
    required this.tabId,
    required this.requests,
    required this.builder,
  });

  final String tabId;
  final List<CodexPendingRequest> requests;
  final Widget Function(CodexPendingRequest request, _CodexQuestionDraft draft)
  builder;

  @override
  State<_CodexPendingQuestionQueue> createState() =>
      _CodexPendingQuestionQueueState();
}

class _CodexPendingQuestionQueueState
    extends State<_CodexPendingQuestionQueue> {
  late Object _activeRequestId;
  final Map<String, _CodexQuestionDraft> _drafts =
      <String, _CodexQuestionDraft>{};

  @override
  void initState() {
    super.initState();
    assert(widget.requests.isNotEmpty);
    _activeRequestId = widget.requests.first.id;
  }

  @override
  void didUpdateWidget(covariant _CodexPendingQuestionQueue oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.requests.isNotEmpty);
    if (_requestIndex < 0) {
      final previousIndex = oldWidget.requests.indexWhere(
        (request) => request.id == _activeRequestId,
      );
      final nextIndex = previousIndex.clamp(0, widget.requests.length - 1);
      _activeRequestId = widget.requests[nextIndex].id;
    }
    _removeStaleDrafts();
  }

  @override
  void dispose() {
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  String _draftKey(CodexPendingRequest request) =>
      _codexQuestionCardStateKey(widget.tabId, request);

  _CodexQuestionDraft _draftFor(CodexPendingRequest request) => _drafts
      .putIfAbsent(_draftKey(request), () => _CodexQuestionDraft(request));

  void _removeStaleDrafts() {
    final activeKeys = <String>{
      for (final request in widget.requests) _draftKey(request),
    };
    for (final key in _drafts.keys.toList(growable: false)) {
      if (activeKeys.contains(key)) continue;
      _drafts.remove(key)?.dispose();
    }
  }

  int get _requestIndex =>
      widget.requests.indexWhere((request) => request.id == _activeRequestId);

  void _select(int index) {
    if (index < 0 || index >= widget.requests.length) return;
    setState(() => _activeRequestId = widget.requests[index].id);
  }

  @override
  Widget build(BuildContext context) {
    final index = _requestIndex < 0 ? 0 : _requestIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.requests.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space24,
              AleraTokens.space8,
              AleraTokens.space24,
              0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AleraTokens.codexQuestionCardMaxWidth,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      'Request ${index + 1} of ${widget.requests.length}',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AleraTokens.foregroundMuted),
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    AleraIconButton(
                      tooltip: 'Previous Pending Question',
                      onPressed: index == 0 ? null : () => _select(index - 1),
                      icon: AleraIcons.chevronLeft,
                      minSize: AleraTokens.space24,
                    ),
                    AleraIconButton(
                      tooltip: 'Next Pending Question',
                      onPressed: index == widget.requests.length - 1
                          ? null
                          : () => _select(index + 1),
                      icon: AleraIcons.chevronRight,
                      minSize: AleraTokens.space24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Flexible(
          fit: FlexFit.loose,
          child: widget.builder(
            widget.requests[index],
            _draftFor(widget.requests[index]),
          ),
        ),
      ],
    );
  }
}
