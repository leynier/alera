import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_elicitation_form.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_cards.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_pager.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_typing_guard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The composer hint while any request waits in the dock.
const String agentChatRequestPendingHint =
    'The agent is waiting for your decision.';

typedef _DraftKey = (String chatId, String requestId);

/// Every request the agent waits on (approvals, MCP forms, questions), docked
/// above the composer one at a time, in the projection's priority order with
/// "Request X of N" paging. The composer stays mounted and keeps its draft;
/// each request keeps its own answers while the person pages, until it is no
/// longer pending. A new request takes the keyboard only when the composer
/// had it (or nothing did), and never within [agentChatTypingIdle] of a
/// keystroke: the takeover waits for a pause, a send, or a blur. No key
/// accepts an approval; Escape on an approval or form returns to the
/// composer.
class const AgentChatRequestDock({
  super.key,
  required final String chatId,
  required final List<AgentChatRequest> requests,
  required final Set<String> respondingRequestIds,
  required final bool enabled,
  required final Future<void> Function(
    AgentChatRequest request,
    AgentChatResponse response,
  )
  onRespond,
  required final TerminalComposerController composer,
  final ValueChanged<String>? onOpenLink,

  /// The most height the dock may take; defaults to a share of the window.
  final double? maxHeight,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatRequestDock> createState() =>
      _AgentChatRequestDockState();
}

class _AgentChatRequestDockState extends ConsumerState<AgentChatRequestDock> {
  final Map<_DraftKey, AgentChatQuestionDraft> _questionDrafts =
      <_DraftKey, AgentChatQuestionDraft>{};
  final Map<_DraftKey, AgentChatElicitationForm> _forms =
      <_DraftKey, AgentChatElicitationForm>{};

  // Observes whether focus is inside the card, so the card that replaces it
  // can keep the keyboard; also the target of a takeover for approvals and
  // forms, which have no single field to start in.
  final FocusNode _cardArea = FocusNode(
    debugLabel: 'Agent chat request dock',
    skipTraversal: true,
  );
  late AgentChatTypingGuard _guard;
  String? _activeRequestId;
  bool _carryFocus = false;
  int _takeover = 0;

  AgentChatTimelineSession get _session =>
      ref.read(agentChatTimelineSessionsProvider).of(widget.chatId);

  @override
  void initState() {
    super.initState();
    _activeRequestId = widget.requests.firstOrNull?.id;
    _guard = _newGuard();
    _noticeArrivals();
  }

  AgentChatTypingGuard _newGuard() => AgentChatTypingGuard(
    text: widget.composer.textController,
    focus: widget.composer.focusNode,
    onRelease: _handleRelease,
    clock: ref.read(agentChatClockProvider),
  );

  @override
  void didUpdateWidget(covariant AgentChatRequestDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.composer, widget.composer)) {
      _guard.dispose();
      _guard = _newGuard();
    }
    final previousKey = (oldWidget.chatId, _activeRequestId);
    if (oldWidget.chatId != widget.chatId) {
      _activeRequestId = widget.requests.firstOrNull?.id;
    } else if (_indexOf(_activeRequestId) < 0) {
      _activeRequestId = _nearestRemaining(oldWidget.requests);
    }
    if ((widget.chatId, _activeRequestId) != previousKey) {
      _carryFocus = _cardArea.hasFocus;
    }
    _dropSettledDrafts();
    if (!identical(oldWidget.requests, widget.requests) ||
        oldWidget.chatId != widget.chatId) {
      _noticeArrivals();
    }
  }

  @override
  void dispose() {
    _guard.dispose();
    for (final draft in _questionDrafts.values) {
      draft.dispose();
    }
    for (final form in _forms.values) {
      form.dispose();
    }
    _cardArea.dispose();
    super.dispose();
  }

  _DraftKey _draftKey(AgentChatRequest request) => (widget.chatId, request.id);

  int _indexOf(String? requestId) =>
      widget.requests.indexWhere((request) => request.id == requestId);

  /// The request closest to where the active one sat in [previous], looking
  /// after it first, since that is the one that takes its place.
  String? _nearestRemaining(List<AgentChatRequest> previous) {
    final requests = widget.requests;
    if (requests.isEmpty) return null;
    final from = previous.indexWhere(
      (request) => request.id == _activeRequestId,
    );
    if (from < 0) return requests.first.id;
    final remaining = <String>{for (final request in requests) request.id};
    for (var distance = 1; distance < previous.length; distance += 1) {
      for (final index in <int>[from + distance, from - distance]) {
        if (index >= 0 &&
            index < previous.length &&
            remaining.contains(previous[index].id)) {
          return previous[index].id;
        }
      }
    }
    return requests[math.min(from, requests.length - 1)].id;
  }

  void _dropSettledDrafts() {
    final pending = <_DraftKey>{
      for (final request in widget.requests) _draftKey(request),
    };
    _questionDrafts.removeWhere((key, draft) {
      if (pending.contains(key)) return false;
      draft.dispose();
      return true;
    });
    _forms.removeWhere((key, form) {
      if (pending.contains(key)) return false;
      form.dispose();
      return true;
    });
  }

  /// Takes the keyboard for the active request when it is new and the
  /// person was in the composer or nowhere, holding it while they type.
  /// Runs before the build that shows the request, so a card that may take
  /// the keyboard mounts focused instead of being rebuilt for it.
  void _noticeArrivals() {
    final seen = _session.seenRequestIds;
    final current = <String>{for (final request in widget.requests) request.id};
    final arrived = current.difference(seen);
    seen
      ..retainAll(current)
      ..addAll(current);
    if (_activeRequestId == null || !arrived.contains(_activeRequestId)) {
      return;
    }
    if (_cardArea.hasFocus) return;
    final composerFocused = widget.composer.focusNode.hasFocus;
    if (!composerFocused && !workbenchFocusIsParked()) return;
    if (_guard.hold()) return;
    _takeFocus(beforeFirstBuild: true);
  }

  void _handleRelease(AgentChatTypingRelease reason) {
    if (!mounted || reason == AgentChatTypingRelease.blurred) return;
    if (!widget.composer.focusNode.hasFocus && !workbenchFocusIsParked()) {
      return;
    }
    _takeFocus(beforeFirstBuild: false);
  }

  /// [beforeFirstBuild] is true when the request's card has not been built
  /// yet: a question card then simply mounts focused. A takeover released
  /// later rebuilds the card instead, which also restarts its Enter guard so
  /// a key meant for the composer cannot answer it.
  void _takeFocus({required bool beforeFirstBuild}) {
    final request = _activeRequest;
    if (request == null) return;
    if (request.isQuestion) {
      if (beforeFirstBuild) {
        _carryFocus = true;
      } else {
        setState(() {
          _takeover += 1;
          _carryFocus = true;
        });
      }
    } else if (beforeFirstBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cardArea.requestFocus();
      });
    } else {
      _cardArea.requestFocus();
    }
  }

  AgentChatRequest? get _activeRequest {
    final index = _indexOf(_activeRequestId);
    return index < 0 ? widget.requests.firstOrNull : widget.requests[index];
  }

  void _select(int index) {
    final requests = widget.requests;
    if (index < 0 || index >= requests.length) return;
    setState(() {
      _carryFocus = _cardArea.hasFocus;
      _activeRequestId = requests[index].id;
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final request = _activeRequest;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        request == null ||
        request.isQuestion) {
      return KeyEventResult.ignored;
    }
    widget.composer.focusNode.requestFocus();
    return KeyEventResult.handled;
  }

  Widget _card(AgentChatRequest request) {
    final key = _draftKey(request);
    final responding = widget.respondingRequestIds.contains(request.id);
    if (request.isQuestion) {
      return AgentChatQuestionCard(
        key: ValueKey<(String, String, int)>((key.$1, key.$2, _takeover)),
        request: request,
        draft: _questionDrafts.putIfAbsent(key, AgentChatQuestionDraft.new),
        responding: responding,
        enabled: widget.enabled,
        takeFocus: _carryFocus,
        onRespond: widget.onRespond,
      );
    }
    final Widget card;
    if (request.isApproval) {
      card = AgentChatApprovalCard(
        key: ValueKey<_DraftKey>(key),
        request: request,
        responding: responding,
        enabled: widget.enabled,
        onDecision: (decision) =>
            widget.onRespond(request, AgentChatApprovalResponse(decision)),
        onDeclineWithFeedback: (feedback) => widget.onRespond(
          request,
          AgentChatApprovalResponse(.decline, feedback: feedback),
        ),
      );
    } else if (request.isElicitation) {
      card = AgentChatElicitationCard(
        key: ValueKey<_DraftKey>(key),
        request: request,
        responding: responding,
        enabled: widget.enabled,
        onOpenUrl: widget.onOpenLink,
        form: _forms.putIfAbsent(
          key,
          () => AgentChatElicitationForm(request.elicitation),
        ),
        onRespond: (action, content) => widget.onRespond(
          request,
          AgentChatElicitationResponse(action, content),
        ),
      );
    } else {
      card = AgentChatUnsupportedRequestCard(
        key: ValueKey<_DraftKey>(key),
        request: request,
        responding: responding,
        enabled: widget.enabled,
        onDecision: (decision) =>
            widget.onRespond(request, AgentChatApprovalResponse(decision)),
      );
    }
    return SingleChildScrollView(child: card);
  }

  @override
  Widget build(BuildContext context) {
    final requests = widget.requests;
    if (requests.isEmpty) return const SizedBox.shrink();
    final index = math.max(0, _indexOf(_activeRequestId));
    final request = requests[index];
    final maxHeight =
        widget.maxHeight ??
        MediaQuery.sizeOf(context).height *
            AleraTokens.agentChatRequestDockHeightFraction;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AleraTokens.agentChatDockMaxWidth,
          maxHeight: maxHeight,
        ),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            key: const ValueKey<String>('agent-chat-request-dock'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (requests.length > 1)
                AgentChatRequestPager(
                  index: index,
                  count: requests.length,
                  onSelect: _select,
                ),
              Flexible(
                child: Focus(
                  focusNode: _cardArea,
                  onKeyEvent: _handleKey,
                  child: _card(request),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
