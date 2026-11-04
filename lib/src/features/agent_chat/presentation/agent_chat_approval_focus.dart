import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_typing_guard.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The keyboard handling the request dock gave approvals, for the approval
/// rows at the end of the timeline. A new approval takes the keyboard only
/// when the composer had it (or nothing did), and never within
/// [agentChatTypingIdle] of a keystroke: the takeover waits for a pause, a
/// send, or a blur. The keyboard lands on the rows, not on a decision, so no
/// key typed for the composer can decide; Tab reaches the decisions and
/// Escape returns to the composer.
class const AgentChatApprovalFocus({
  super.key,
  required final String chatId,

  /// The pending approvals [child] shows.
  required final List<AgentChatRequest> approvals,
  required final TerminalComposerController composer,
  required final Widget child,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatApprovalFocus> createState() =>
      _AgentChatApprovalFocusState();
}

class _AgentChatApprovalFocusState
    extends ConsumerState<AgentChatApprovalFocus> {
  final FocusNode _area = FocusNode(
    debugLabel: 'Agent chat pending approvals',
    skipTraversal: true,
  );
  late AgentChatTypingGuard _guard;

  @override
  void initState() {
    super.initState();
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
  void didUpdateWidget(covariant AgentChatApprovalFocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.composer, widget.composer)) {
      _guard.dispose();
      _guard = _newGuard();
    }
    if (!identical(oldWidget.approvals, widget.approvals) ||
        oldWidget.chatId != widget.chatId) {
      _noticeArrivals();
    }
  }

  @override
  void dispose() {
    _guard.dispose();
    _area.dispose();
    super.dispose();
  }

  /// Takes the keyboard when an approval arrived and the person was in the
  /// composer or nowhere, holding it while they type.
  void _noticeArrivals() {
    final seen = ref
        .read(agentChatTimelineSessionsProvider)
        .of(widget.chatId)
        .seenApprovalIds;
    final current = <String>{
      for (final request in widget.approvals) request.id,
    };
    final arrived = current.difference(seen);
    seen
      ..retainAll(current)
      ..addAll(current);
    if (arrived.isEmpty || _area.hasFocus) return;
    if (!widget.composer.focusNode.hasFocus && !workbenchFocusIsParked()) {
      return;
    }
    if (_guard.hold()) return;
    // The rows mount with the approvals; focus them once they are built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeFocus());
  }

  void _handleRelease(AgentChatTypingRelease reason) {
    if (!mounted || reason == AgentChatTypingRelease.blurred) return;
    if (!widget.composer.focusNode.hasFocus && !workbenchFocusIsParked()) {
      return;
    }
    _takeFocus();
  }

  void _takeFocus() {
    if (!mounted || widget.approvals.isEmpty) return;
    _area.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    widget.composer.focusNode.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Focus(focusNode: _area, onKeyEvent: _handleKey, child: widget.child),
  );
}
