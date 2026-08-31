part of 'mobile_codex_chat_screen.dart';

class const _MobilePlanCard({
  required final MobileCodexTimelineCell cell,
  required final bool previous,
  required final VoidCallback onOpen,
  required final bool initiallyOverflowing,
  required final ValueChanged<bool> onOverflowChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final title = previous
        ? 'Previous Plan'
        : cell.isStreaming
        ? 'Writing Plan'
        : 'Plan';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      child: Hero(
        tag: 'mobile-codex-plan-${cell.id}',
        flightShuttleBuilder: (_, _, _, _, _) => const _MobilePlanFlightShell(),
        child: Material(
          color: AleraTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            side: const BorderSide(color: AleraTokens.border),
          ),
          clipBehavior: .antiAlias,
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              _MobilePlanHeader(
                title: title,
                streaming: cell.isStreaming,
                text: _mobilePlanActionText(cell),
                onOpen: onOpen,
              ),
              if (!previous)
                _MobilePlanPreview(
                  key: ValueKey<String>('mobile-codex-plan-preview-${cell.id}'),
                  initiallyOverflowing: initiallyOverflowing,
                  preserveOverflow: cell.isStreaming,
                  onOverflowChanged: onOverflowChanged,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.space16,
                      0,
                      AleraTokens.space16,
                      AleraTokens.space16,
                    ),
                    child: _MobileCodexMarkdown(text: cell.displayText),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _MobilePlanHeader({
  required final String title,
  required final bool streaming,
  required final String text,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space12,
      vertical: AleraTokens.space8,
    ),
    child: Row(
      children: <Widget>[
        Icon(
          streaming ? Icons.lightbulb : Icons.lightbulb_outline,
          size: AleraTokens.space16,
          color: streaming
              ? AleraTokens.foreground
              : AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: streaming
              ? _MobileCodexShimmerText(
                  text: title,
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Text(title, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Builder(
          builder: (shareContext) => IconButton(
            tooltip: 'Download Plan',
            visualDensity: .compact,
            onPressed: () => unawaited(_sharePlan(shareContext, text)),
            icon: const Icon(
              Icons.download_outlined,
              size: AleraTokens.space16,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy Plan',
          visualDensity: .compact,
          onPressed: () =>
              unawaited(Clipboard.setData(ClipboardData(text: text))),
          icon: const Icon(Icons.copy_outlined, size: AleraTokens.space16),
        ),
        IconButton(
          tooltip: 'Maximize Plan',
          visualDensity: .compact,
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_full, size: AleraTokens.space16),
        ),
      ],
    ),
  );
}

class const _MobilePlanFlightShell() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      border: Border.all(color: AleraTokens.border),
    ),
  );
}

class const _MobileExpandedPlanScreen({
  required final String hostId,
  required final String tabId,
  required final String workspaceId,
  required final String? cwd,
  required final String cellId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = mobileCodexControllerProvider(hostId, tabId);
    final value = ref.watch(provider);
    final state = value.value;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cell = state.timelineCells
        .where((item) => item.id == cellId)
        .firstOrNull;
    if (cell == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plan')),
        body: const Center(child: Text('This plan is no longer available.')),
      );
    }
    final controller = ref.read(provider.notifier);
    return _MobileCodexWorkspaceScope(
      hostId: hostId,
      workspaceId: workspaceId,
      cwd: cwd,
      child: Scaffold(
        appBar: AppBar(title: Text(cell.isStreaming ? 'Writing Plan' : 'Plan')),
        body: SafeArea(
          child: Padding(
            padding: AleraTokens.contentPadding,
            child: Hero(
              tag: 'mobile-codex-plan-${cell.id}',
              flightShuttleBuilder: (_, _, _, _, _) =>
                  const _MobilePlanFlightShell(),
              child: Material(
                color: AleraTokens.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  side: const BorderSide(color: AleraTokens.border),
                ),
                clipBehavior: .antiAlias,
                child: Column(
                  children: <Widget>[
                    _MobilePlanHeader(
                      title: cell.isStreaming ? 'Writing Plan' : 'Plan',
                      streaming: cell.isStreaming,
                      text: _mobilePlanActionText(cell),
                      onOpen: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: AleraTokens.contentPadding,
                        child: _MobileCodexMarkdown(text: cell.displayText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar:
            state.shouldShowImplementPlan &&
                state.latestActionablePlan?.id == cell.id
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AleraTokens.space12),
                  child: _MobilePlanPrompt(
                    state: state,
                    controller: controller,
                    onResolved: () {
                      if (context.mounted) {
                        Navigator.of(context).maybePop();
                      }
                    },
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

String _mobilePlanActionText(MobileCodexTimelineCell cell) =>
    cell.markdownText ?? cell.displayText;

class const _MobilePlanPrompt({
  required final MobileCodexState state,
  required final MobileCodexController controller,
  final VoidCallback? onResolved,
}) extends StatefulWidget {
  @override
  State<_MobilePlanPrompt> createState() => _MobilePlanPromptState();
}

class _MobilePlanPromptState extends State<_MobilePlanPrompt> {
  final TextEditingController _refinement = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _refinement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    ),
    padding: const EdgeInsets.all(AleraTokens.space12),
    child: Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Implement this plan?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Dismiss Plan',
              visualDensity: .compact,
              onPressed: () => unawaited(_decline()),
              icon: const Icon(Icons.close, size: AleraTokens.space16),
            ),
          ],
        ),
        _MobileChoiceRow(
          leading: '1',
          title: 'Yes, Implement This Plan',
          trailing: Icons.chevron_right,
          onTap: () => unawaited(_implement()),
        ),
        const SizedBox(height: AleraTokens.space6),
        _MobileInlineAnswer(
          controller: _refinement,
          active: _editing,
          hintText: 'No, and tell Codex what to do differently',
          submitLabel: 'Submit',
          obscureText: false,
          onActivate: () => setState(() => _editing = true),
          onSubmit: () => unawaited(_refine()),
          onSkip: () => unawaited(_decline()),
        ),
        const SizedBox(height: AleraTokens.space8),
        Align(
          alignment: Alignment.centerLeft,
          child: _MobileModelMenuButton(
            state: widget.state,
            onModel: widget.controller.setModel,
            onReasoning: widget.controller.setReasoning,
            onSpeed: widget.controller.setSpeed,
            onCollaboration: widget.controller.setCollaborationMode,
          ),
        ),
      ],
    ),
  );

  Future<void> _implement() async {
    await widget.controller.implementPlan();
    widget.onResolved?.call();
  }

  Future<void> _decline() async {
    await widget.controller.declinePlan();
    widget.onResolved?.call();
  }

  Future<void> _refine() async {
    final value = _refinement.text.trim();
    if (value.isEmpty) return;
    await widget.controller.refinePlan(value);
    widget.onResolved?.call();
  }
}

class const _MobilePlanProgress({
  required final int current,
  required final int total,
  required final List<Map<String, Object?>> items,
}) {
  static _MobilePlanProgress? fromCells(
    List<MobileCodexTimelineCell> cells, {
    required String? activeTurnId,
  }) {
    if (activeTurnId == null) return null;
    for (final cell in cells.reversed) {
      if (cell.turnId != activeTurnId) continue;
      final raw = cell.metadata['plan'];
      if (raw is! List || raw.isEmpty) continue;
      final items = <Map<String, Object?>>[
        for (final item in raw)
          if (item is Map) Map<String, Object?>.from(item),
      ];
      if (items.isEmpty) continue;
      final completed = items.where((item) {
        final status = item['status']?.toString().toLowerCase();
        return status == 'completed' || status == 'done';
      }).length;
      return _MobilePlanProgress(
        current: (completed + 1).clamp(1, items.length),
        total: items.length,
        items: List<Map<String, Object?>>.unmodifiableOf(items),
      );
    }
    return null;
  }
}

Future<void> _sharePlan(BuildContext context, String text) async {
  final shared = await shareMobileCodexPlanText(
    text,
    sharePositionOrigin: mobileCodexSharePositionOrigin(context),
  );
  if (!shared && context.mounted) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Could not share plan.')));
  }
}

@visibleForTesting
Future<bool> shareMobileCodexPlanText(
  String text, {
  required Rect sharePositionOrigin,
  Future<ShareResult> Function(ShareParams params)? share,
}) async {
  final params = ShareParams(
    files: <XFile>[
      XFile.fromData(
        .fromList(utf8.encode(text)),
        mimeType: 'text/markdown',
        name: 'plan.md',
      ),
    ],
    fileNameOverrides: const <String>['plan.md'],
    subject: 'Codex Plan',
    sharePositionOrigin: sharePositionOrigin,
  );
  try {
    await (share ?? SharePlus.instance.share)(params);
    return true;
  } on Object catch (error, stackTrace) {
    _MobileCodexChatScreenState._logger.warning(
      'Could not share plan.',
      error,
      stackTrace,
    );
    return false;
  }
}
