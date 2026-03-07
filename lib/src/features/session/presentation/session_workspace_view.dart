import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/presentation/widgets/approval_card.dart';
import 'package:alera/src/features/session/presentation/widgets/chat_timeline_list.dart';
import 'package:alera/src/features/session/presentation/widgets/composer.dart';
import 'package:alera/src/features/session/presentation/widgets/composer_text_controller.dart';
import 'package:alera/src/features/session/presentation/widgets/message_queue_bar.dart';
import 'package:alera/src/features/session/presentation/widgets/raw_log.dart';
import 'package:alera/src/features/session/presentation/widgets/user_input_card.dart';
import 'package:flutter/material.dart';

// Re-export for test compatibility.
export 'package:alera/src/features/session/presentation/widgets/markdown_helpers.dart'
    show copyMouseConnectionDetector;

class SessionWorkspaceView extends StatefulWidget {
  const SessionWorkspaceView({
    super.key,
    required this.state,
    required this.onSendInput,
    required this.onInterruptTurn,
    required this.isTurnRunning,
    required this.isInterrupting,
    required this.onModelChanged,
    required this.activeReasoningEffort,
    required this.supportedReasoningEfforts,
    required this.onReasoningEffortChanged,
    required this.isMarkdownEnabled,
    required this.onMarkdownModeChanged,
    required this.rawLogExpanded,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.onRemoveFromQueue,
    required this.onPlanModeToggled,
    required this.onImplementPlanPressed,
    required this.onPermissionModeToggled,
    required this.onApproveRequest,
    required this.onDeclineRequest,
    required this.onSubmitUserInput,
    required this.onDismissUserInput,
  });

  final SessionState state;
  final ValueChanged<String> onSendInput;
  final VoidCallback onInterruptTurn;
  final bool isTurnRunning;
  final bool isInterrupting;
  final ValueChanged<String> onModelChanged;
  final String activeReasoningEffort;
  final List<String> supportedReasoningEfforts;
  final ValueChanged<String> onReasoningEffortChanged;
  final bool isMarkdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;
  final bool rawLogExpanded;
  final VoidCallback onAddAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<String> onRemoveFromQueue;
  final VoidCallback onPlanModeToggled;
  final Future<void> Function() onImplementPlanPressed;
  final VoidCallback onPermissionModeToggled;
  final Future<void> Function(Object requestId, {bool forSession})
  onApproveRequest;
  final Future<void> Function(Object requestId) onDeclineRequest;
  final ValueChanged<Map<String, dynamic>> onSubmitUserInput;
  final VoidCallback onDismissUserInput;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  static const double _contentMaxWidth = 720;
  static const double _timelineExtraInset = AleraTokens.space8;
  static const double _timelineContentMaxWidth =
      _contentMaxWidth - (AleraTokens.space12 * 2) - _timelineExtraInset;
  static const double _bottomTolerancePx = 1;

  late final _inputController = ComposerTextController()
    ..workspacePath = widget.state.selectedWorkspacePath;
  final Set<String> _expandedWorkedTurns = <String>{};
  final ScrollController _timelineScrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _pendingScrollAfterSend = false;

  @override
  void initState() {
    super.initState();
    _timelineScrollController.addListener(_handleTimelineScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant SessionWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.selectedWorkspacePath !=
        widget.state.selectedWorkspacePath) {
      _inputController.workspacePath = widget.state.selectedWorkspacePath;
    }
    if (oldWidget.state.activeSessionId != widget.state.activeSessionId) {
      _expandedWorkedTurns.clear();
    }
    final timelineChanged = !identical(
      oldWidget.state.timelineCells,
      widget.state.timelineCells,
    );
    final hasNonUserTimelineChanges =
        timelineChanged &&
        _hasNonUserTimelineChanges(
          oldWidget.state.timelineCells,
          widget.state.timelineCells,
        );
    final shouldAutoScrollForAi =
        hasNonUserTimelineChanges &&
        _isAtBottom(tolerancePx: _bottomTolerancePx);
    final shouldAutoScrollForSend = _pendingScrollAfterSend && timelineChanged;
    if (shouldAutoScrollForAi || shouldAutoScrollForSend) {
      _scheduleScrollToBottom(animated: shouldAutoScrollForSend);
      if (shouldAutoScrollForSend) {
        _pendingScrollAfterSend = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _timelineScrollController.removeListener(_handleTimelineScroll);
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasWorkspace =
        (widget.state.selectedWorkspacePath != null &&
            widget.state.selectedWorkspacePath!.isNotEmpty) ||
        widget.state.activeSession != null;
    final shouldShowImplementPlanButton = _shouldShowImplementPlanButton();
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ChatTimelineList(
                  state: widget.state,
                  expandedWorkedTurns: _expandedWorkedTurns,
                  onToggleWorkedTurn: _toggleWorkedTurn,
                  controller: _timelineScrollController,
                  markdownEnabled: widget.isMarkdownEnabled,
                  onMarkdownModeChanged: widget.onMarkdownModeChanged,
                  contentMaxWidth: _timelineContentMaxWidth,
                  showImplementPlanButton: shouldShowImplementPlanButton,
                  onImplementPlanPressed: _onImplementPlanPressed,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space12),
                  child: IgnorePointer(
                    ignoring: !_showScrollToBottom,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: _showScrollToBottom ? 1 : 0,
                      child: IconButton(
                        key: const ValueKey<String>('scroll-to-bottom-button'),
                        onPressed: _showScrollToBottom
                            ? () => _scheduleScrollToBottom(animated: true)
                            : null,
                        mouseCursor: SystemMouseCursors.click,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: AleraTokens.bg,
                          foregroundColor: AleraTokens.foreground,
                          side: const BorderSide(
                            color: AleraTokens.border,
                            width: 1,
                          ),
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.arrow_downward, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.state.pendingApprovals.isNotEmpty)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: Column(
                  children: widget.state.pendingApprovals
                      .map((approval) {
                        return ApprovalCard(
                          approval: approval,
                          onApprove: () => widget.onApproveRequest(
                            approval.requestId,
                            forSession: false,
                          ),
                          onApproveForSession: () => widget.onApproveRequest(
                            approval.requestId,
                            forSession: true,
                          ),
                          onDecline: () =>
                              widget.onDeclineRequest(approval.requestId),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        if (widget.state.pendingUserInput != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: UserInputCard(
                  pendingUserInput: widget.state.pendingUserInput!,
                  onSubmit: widget.onSubmitUserInput,
                  onDismiss: widget.onDismissUserInput,
                ),
              ),
            ),
          ),
        if (widget.state.pendingMessages.isNotEmpty)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
              child: MessageQueueBar(
                messages: widget.state.pendingMessages,
                onRemove: widget.onRemoveFromQueue,
              ),
            ),
          ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: Composer(
              controller: _inputController,
              textFieldEnabled: hasWorkspace,
              canSend:
                  hasWorkspace &&
                  !widget.state.isBusy &&
                  !widget.isInterrupting,
              canStop:
                  widget.state.activeSession != null &&
                  widget.isTurnRunning &&
                  !widget.state.isBusy,
              canChangeModel: hasWorkspace,
              isBusy: widget.state.isBusy,
              isInterrupting: widget.isInterrupting,
              activeModelId: widget.state.activeModelId,
              availableModels: widget.state.availableModels,
              onModelChanged: widget.onModelChanged,
              activeReasoningEffort: widget.activeReasoningEffort,
              supportedReasoningEfforts: widget.supportedReasoningEfforts,
              onReasoningEffortChanged: widget.onReasoningEffortChanged,
              hintText: widget.state.activeSession != null
                  ? 'Ask for follow-up changes'
                  : 'Ask Alera anything, @ to add files, / for commands',
              onSend: _sendInput,
              onInterrupt: widget.onInterruptTurn,
              attachments: widget.state.composerAttachments,
              onAddAttachment: hasWorkspace ? widget.onAddAttachment : null,
              onRemoveAttachment: widget.onRemoveAttachment,
              workspacePath: widget.state.selectedWorkspacePath,
              planModeEnabled: widget.state.planModeEnabled,
              onPlanModeToggled: hasWorkspace ? widget.onPlanModeToggled : null,
              fullAccessEnabled:
                  widget.state.permissionMode == PermissionMode.fullAccess,
              onPermissionModeToggled: hasWorkspace
                  ? widget.onPermissionModeToggled
                  : null,
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: RawLog(state: widget.state, expanded: widget.rawLogExpanded),
          ),
        ),
      ],
    );
  }

  void _sendInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    _pendingScrollAfterSend = true;
    _scheduleScrollToBottom(animated: true);
    widget.onSendInput(text);
  }

  void _onImplementPlanPressed() {
    unawaited(widget.onImplementPlanPressed());
  }

  void _toggleWorkedTurn(String turnId) {
    setState(() {
      if (_expandedWorkedTurns.contains(turnId)) {
        _expandedWorkedTurns.remove(turnId);
      } else {
        _expandedWorkedTurns.add(turnId);
      }
    });
  }

  bool _hasNonUserTimelineChanges(
    List<TimelineCell> previous,
    List<TimelineCell> next,
  ) {
    final previousById = <String, TimelineCell>{
      for (final cell in previous) cell.id: cell,
    };
    for (final cell in next) {
      final old = previousById.remove(cell.id);
      if (old == null) {
        if (cell.kind != TimelineCellKind.userMessage) {
          return true;
        }
        continue;
      }
      if (_hasCellChanged(old, cell) &&
          cell.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }
    for (final removed in previousById.values) {
      if (removed.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }
    return false;
  }

  bool _hasCellChanged(TimelineCell previous, TimelineCell next) {
    return previous.status != next.status ||
        previous.updatedAt != next.updatedAt ||
        previous.isStreaming != next.isStreaming ||
        previous.isCollapsed != next.isCollapsed ||
        previous.title != next.title ||
        previous.subtitle != next.subtitle ||
        previous.markdownText != next.markdownText ||
        previous.detailsText != next.detailsText;
  }

  bool _shouldShowImplementPlanButton() {
    if (widget.state.pendingMessages.isNotEmpty) {
      return false;
    }
    var lastPlanIndex = -1;
    var lastUserMessageIndex = -1;
    final cells = widget.state.timelineCells;
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (cell.kind == TimelineCellKind.plan) {
        lastPlanIndex = i;
      } else if (cell.kind == TimelineCellKind.userMessage) {
        lastUserMessageIndex = i;
      }
    }
    return lastPlanIndex != -1 && lastPlanIndex > lastUserMessageIndex;
  }

  void _handleTimelineScroll() {
    _updateScrollToBottomVisibility();
  }

  bool _isAtBottom({required double tolerancePx}) {
    if (!_timelineScrollController.hasClients) {
      return true;
    }
    final position = _timelineScrollController.position;
    final distanceToBottom = (position.maxScrollExtent - position.pixels).clamp(
      0.0,
      double.infinity,
    );
    return distanceToBottom <= tolerancePx;
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted) {
      return;
    }
    if (!_timelineScrollController.hasClients) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }
    final shouldShow = !_isAtBottom(tolerancePx: _bottomTolerancePx);
    if (shouldShow == _showScrollToBottom) {
      return;
    }
    setState(() {
      _showScrollToBottom = shouldShow;
    });
  }

  void _scheduleScrollToBottom({bool animated = false}) {
    _scrollToBottomIfPossible(animated: animated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomIfPossible(animated: animated);
    });
  }

  bool _scrollToBottomIfPossible({required bool animated}) {
    if (!mounted || !_timelineScrollController.hasClients) {
      return false;
    }
    final target = _timelineScrollController.position.maxScrollExtent;
    if (animated) {
      _timelineScrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_updateScrollToBottomVisibility);
      return true;
    }
    _timelineScrollController.jumpTo(target);
    _updateScrollToBottomVisibility();
    return true;
  }
}
