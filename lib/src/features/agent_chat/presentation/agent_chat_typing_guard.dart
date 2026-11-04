import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';

/// Why a held focus takeover was released.
enum AgentChatTypingRelease {
  /// Typing paused for [agentChatTypingIdle].
  idle,

  /// The composer sent its draft (its text went from something to nothing).
  sent,

  /// The composer lost focus; the person went elsewhere, so nothing takes
  /// the focus after all.
  blurred,
}

/// Watches the composer so a request that arrives mid-sentence never pulls
/// the caret away: while the person typed within the last
/// [agentChatTypingIdle], a takeover is held, and released once typing
/// pauses, the draft is sent, or the composer loses focus. The draft itself
/// is never touched.
///
/// A guard created while the composer has focus cannot know when the last
/// key was pressed, so it assumes just now: the request dock mounts with its
/// first request, and a takeover then waits one idle period rather than risk
/// landing mid-word.
final class AgentChatTypingGuard {
  AgentChatTypingGuard({
    required this.text,
    required this.focus,
    required this.onRelease,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _lastText = text.text;
    if (focus.hasFocus) _lastKeystroke = _clock();
    text.addListener(_handleText);
    focus.addListener(_handleFocus);
  }

  final TextEditingController text;
  final FocusNode focus;
  final void Function(AgentChatTypingRelease reason) onRelease;
  final DateTime Function() _clock;

  late String _lastText;
  DateTime? _lastKeystroke;
  bool _holding = false;
  Timer? _idle;

  /// Whether a takeover right now would interrupt typing.
  bool get typing =>
      focus.hasFocus &&
      !agentChatRequestMayTakeFocus(
        now: _clock(),
        lastKeystroke: _lastKeystroke,
      );

  bool get holding => _holding;

  /// Holds a takeover until typing pauses. Returns false when nothing needs
  /// holding and the caller may take the focus now.
  bool hold() {
    if (!typing) return false;
    _holding = true;
    _scheduleIdle();
    return true;
  }

  void _handleText() {
    final next = text.text;
    if (next == _lastText) return;
    final previous = _lastText;
    _lastText = next;
    if (next.isEmpty && previous.trim().isNotEmpty) {
      _release(AgentChatTypingRelease.sent);
      return;
    }
    _lastKeystroke = _clock();
    if (_holding) _scheduleIdle();
  }

  void _handleFocus() {
    if (!focus.hasFocus) _release(AgentChatTypingRelease.blurred);
  }

  void _scheduleIdle() {
    _idle?.cancel();
    final last = _lastKeystroke;
    final wait = last == null
        ? Duration.zero
        : agentChatTypingIdle - _clock().difference(last);
    _idle = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (typing) {
        _scheduleIdle();
      } else {
        _release(AgentChatTypingRelease.idle);
      }
    });
  }

  void _release(AgentChatTypingRelease reason) {
    _idle?.cancel();
    _idle = null;
    _lastKeystroke = null;
    if (!_holding) return;
    _holding = false;
    onRelease(reason);
  }

  void dispose() {
    _idle?.cancel();
    text.removeListener(_handleText);
    focus.removeListener(_handleFocus);
  }
}
