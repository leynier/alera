import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_composer_draft_store.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_controller.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_catalog_selection.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_composer_draft.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_file_reference.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_saved_prompt_expander.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/infra/prompt_image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

part 'mobile_codex_chat_composer.dart';
part 'mobile_codex_chat_composer_attachments.dart';
part 'mobile_codex_chat_composer_controls.dart';
part 'mobile_codex_chat_catalog.dart';
part 'mobile_codex_chat_catalog_support.dart';
part 'mobile_codex_chat_catalog_model_menu.dart';
part 'mobile_codex_chat_attachments.dart';
part 'mobile_codex_chat_timeline.dart';
part 'mobile_codex_chat_activity.dart';
part 'mobile_codex_chat_notices.dart';
part 'mobile_codex_chat_plan.dart';
part 'mobile_codex_chat_requests.dart';
part 'mobile_codex_chat_elicitation.dart';
part 'mobile_codex_chat_markdown.dart';
part 'mobile_codex_chat_links.dart';
part 'mobile_codex_chat_viewer.dart';
part 'mobile_codex_chat_file_preview.dart';
part 'mobile_codex_chat_view_state.dart';
part 'mobile_codex_chat_dialogs.dart';
part 'mobile_codex_chat_secondary.dart';
part 'mobile_codex_chat_shimmer.dart';
part 'mobile_codex_resume_picker.dart';
part 'mobile_codex_chat_footer.dart';
part 'mobile_codex_chat_screen_actions.dart';
part 'mobile_codex_chat_history_actions.dart';
part 'mobile_codex_chat_submission_actions.dart';
part 'mobile_codex_chat_attachment_actions.dart';

class MobileCodexChatScreen extends ConsumerStatefulWidget {
  const MobileCodexChatScreen({
    super.key,
    required this.hostId,
    required this.tabId,
    required this.workspaceId,
    this.onFocusBoundTab,
  });

  final String hostId;
  final String tabId;
  final String workspaceId;
  final void Function(String workspaceId, String tabId)? onFocusBoundTab;

  @override
  ConsumerState<MobileCodexChatScreen> createState() =>
      _MobileCodexChatScreenState();
}

class _MobileCodexChatScreenState extends ConsumerState<MobileCodexChatScreen> {
  static final Logger _logger = Logger('MobileCodexChatScreen');
  late final TextEditingController _composer;
  late final FocusNode _composerFocus;
  final ScrollController _timeline = ScrollController();
  final List<Map<String, Object?>> _attachments = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _catalogSelections =
      <Map<String, Object?>>[];
  late final MobileCodexComposerDraftStore _draftStore;
  bool _restoringDraft = false;
  bool _loadingEarlier = false;
  List<MobileCodexPresentationRow>? _historyRowsOverride;
  Set<String>? _historyOriginalCellIds;
  final GlobalKey _historyAnchorKey = GlobalKey();
  final Set<String> _expandedActivityGroups = <String>{};
  List<MobileCodexPresentationRow>? _timelineRowIndexSource;
  Map<String, int> _timelineRowIndexes = const <String, int>{};
  String? _historyAnchorCellId;
  bool _timelinePinScheduled = false;
  bool _timelinePinRequested = false;
  bool _animateTimelinePin = false;
  bool? _timelinePinned;
  int _submissionRevision = 0;
  final Map<String, int> _pendingSubmissionCounts = <String, int>{};
  Future<void> _submissionTail = Future<void>.value();
  late TextEditingValue _lastComposerValue;

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(mobileCodexComposerDraftStoreProvider);
    _draftStore.activate(widget.hostId, widget.tabId);
    final draft = _draftStore.read(widget.hostId, widget.tabId);
    _composer = TextEditingController.fromValue(draft.value);
    _lastComposerValue = draft.value;
    _attachments.addAll(draft.attachments);
    _catalogSelections.addAll(draft.catalogSelections);
    _composer.addListener(_persistDraft);
    _composerFocus = FocusNode();
    _timeline.addListener(_handleTimelineScroll);
    _draftStore.addRestoreListener(
      widget.hostId,
      widget.tabId,
      _handleRestoredDraft,
    );
  }

  @override
  void dispose() {
    _submissionRevision += 1;
    _draftStore.removeRestoreListener(
      widget.hostId,
      widget.tabId,
      _handleRestoredDraft,
    );
    _timeline.removeListener(_handleTimelineScroll);
    _composer.removeListener(_persistDraft);
    _composer.dispose();
    _composerFocus.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MobileCodexChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hostId != widget.hostId || oldWidget.tabId != widget.tabId) {
      _submissionRevision += 1;
      _submissionTail = Future<void>.value();
      _draftStore.removeRestoreListener(
        oldWidget.hostId,
        oldWidget.tabId,
        _handleRestoredDraft,
      );
      _draftStore.activate(widget.hostId, widget.tabId);
      _draftStore.addRestoreListener(
        widget.hostId,
        widget.tabId,
        _handleRestoredDraft,
      );
      _expandedActivityGroups.clear();
      _timelineRowIndexSource = null;
      _timelineRowIndexes = const <String, int>{};
      _timelinePinned = null;
      _restoreDraft();
    }
  }

  void _handleRestoredDraft() {
    if (!mounted) return;
    _restoreDraft();
    setState(() {});
  }

  void _setDraftState(VoidCallback callback) {
    setState(callback);
    _persistDraft();
  }

  void _restoreDraft() {
    final draft = _draftStore.read(widget.hostId, widget.tabId);
    _restoringDraft = true;
    _composer.value = draft.value;
    _lastComposerValue = draft.value;
    _attachments
      ..clear()
      ..addAll(draft.attachments);
    _catalogSelections
      ..clear()
      ..addAll(draft.catalogSelections);
    _restoringDraft = false;
  }

  void _persistDraft() {
    if (_restoringDraft) return;
    final nextValue = _composer.value;
    final rebasedSelections = mobileCodexRebaseCatalogSelections(
      _lastComposerValue,
      nextValue,
      _catalogSelections,
    );
    _catalogSelections
      ..clear()
      ..addAll(rebasedSelections);
    _lastComposerValue = nextValue;
    _draftStore.write(
      widget.hostId,
      widget.tabId,
      MobileCodexComposerDraft(
        value: nextValue,
        attachments: List<Map<String, Object?>>.unmodifiable(
          _attachments.map(Map<String, Object?>.unmodifiable),
        ),
        catalogSelections: List<Map<String, Object?>>.unmodifiable(
          _activeCatalogSelections().map(Map<String, Object?>.unmodifiable),
        ),
      ),
    );
  }

  List<Map<String, Object?>> _activeCatalogSelections() {
    return mobileCodexActiveCatalogSelections(
      _composer.text,
      _catalogSelections,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = mobileCodexControllerProvider(widget.hostId, widget.tabId);
    final value = ref.watch(
      provider.select(
        (value) => (
          loading: value.isLoading,
          error: value.error,
          ready: value.hasValue,
          activeCwd: value.value?.activeCwd,
        ),
      ),
    );
    final controller = ref.read(provider.notifier);
    if (value.error != null) {
      return _MobileError(
        message: value.error.toString(),
        onRetry: () => ref.invalidate(provider),
      );
    }
    if (!value.ready) return const Center(child: CircularProgressIndicator());
    return _buildChat(
      context,
      provider,
      controller,
      activeCwd: value.activeCwd,
    );
  }

  Widget _buildChat(
    BuildContext context,
    MobileCodexControllerProvider provider,
    MobileCodexController controller, {
    String? activeCwd,
  }) {
    final shimmering = ref.watch(
      provider.select((value) {
        final state = value.value;
        return state?.busy == true ||
            state?.mcpInitializing == true ||
            state?.timelineCells.any((cell) => cell.isStreaming) == true;
      }),
    );
    final lifecycle = ref.watch(appLifecycleControllerProvider);
    final animateShimmer =
        shimmering &&
        lifecycle == AppLifecycleState.resumed &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    return _MobileCodexWorkspaceScope(
      hostId: widget.hostId,
      workspaceId: widget.workspaceId,
      cwd: activeCwd,
      child: LayoutBuilder(
        builder: (context, constraints) => _MobileCodexShimmerScope(
          enabled: animateShimmer,
          child: Column(
            children: <Widget>[
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(
                      provider.select((value) => value.value!),
                    );
                    final rows = _historyRowsOverride ?? state.presentationRows;
                    _scheduleTimelinePin();
                    return CustomScrollView(
                      controller: _timeline,
                      slivers: <Widget>[
                        if (state.historyNextCursor != null)
                          SliverToBoxAdapter(
                            child: TextButton(
                              onPressed: _loadingEarlier
                                  ? null
                                  : () {
                                      if (_loadingEarlier) return;
                                      _loadingEarlier = true;
                                      unawaited(
                                        _loadEarlierHistory(
                                          controller,
                                          state.historyNextCursor!,
                                        ),
                                      );
                                    },
                              child: const Text('Load Earlier Messages'),
                            ),
                          ),
                        SliverPadding(
                          padding: AleraTokens.contentPadding,
                          sliver: rows.isEmpty
                              ? const SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      'Ask Codex to work on this workspace.',
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    final child = _MobileTimelineRow(
                                      row: row,
                                      onOpenPlan: _openPlan,
                                      activityExpanded: _expandedActivityGroups
                                          .contains(row.id),
                                      onToggleActivity: () {
                                        setState(() {
                                          if (!_expandedActivityGroups.add(
                                            row.id,
                                          )) {
                                            _expandedActivityGroups.remove(
                                              row.id,
                                            );
                                          }
                                        });
                                      },
                                    );
                                    return KeyedSubtree(
                                      key: ValueKey<String>(row.id),
                                      child: _historyRowContainsAnchor(row)
                                          ? KeyedSubtree(
                                              key: _historyAnchorKey,
                                              child: child,
                                            )
                                          : child,
                                    );
                                  },
                                  findChildIndexCallback: (key) =>
                                      _findTimelineRowIndex(rows, key),
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final state = ref
                      .watch(
                        provider.select(
                          (value) => _MobileFooterState(value.value!),
                        ),
                      )
                      .state;
                  return _buildFooter(
                    context,
                    state,
                    controller,
                    availableHeight: constraints.maxHeight,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _showScrollToBottom = false;
}
