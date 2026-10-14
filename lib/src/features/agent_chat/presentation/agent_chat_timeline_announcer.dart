import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Screen reader announcements for what changes without the reader moving:
/// a new request, a turn that settles, a message that failed to send. Each
/// is announced once, on the transition between two projections, so a
/// remounted timeline never repeats an old one.
abstract final class AgentChatTimelineAnnouncer {
  static void announce(
    BuildContext context, {
    required AgentChatTimelineProjection before,
    required AgentChatTimelineProjection after,
  }) {
    final messages = transitions(before: before, after: after);
    if (messages.isEmpty) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    for (final message in messages) {
      unawaited(SemanticsService.sendAnnouncement(view, message, direction));
    }
  }

  /// The announcements between [before] and [after], oldest event first.
  static List<String> transitions({
    required AgentChatTimelineProjection before,
    required AgentChatTimelineProjection after,
  }) {
    final messages = <String>[];
    final pending = <String>{for (final request in before.requests) request.id};
    for (final request in after.requests) {
      if (pending.contains(request.id)) continue;
      final title = agentChatRequestTitle(request).trim();
      final sentence = RegExp(r'[.?!]$').hasMatch(title) ? title : '$title.';
      messages.add('$sentence The agent is waiting for your decision.');
    }
    for (final entry in after.entries) {
      switch (entry) {
        case AgentChatTurnEntry(:final section) when !section.working:
          final previous = before.sectionFor(section.turnId);
          if (previous == null || !previous.working) continue;
          messages.add(_settled(section.outcome));
        case AgentChatOutgoingEntry(:final message)
            when message.status == AgentChatOutgoingStatus.failed:
          final index = before.indexOfKey(entry.key);
          final previous = index == null ? null : before.entries[index];
          if (previous case AgentChatOutgoingEntry(message: final old)
              when old.status == AgentChatOutgoingStatus.failed) {
            continue;
          }
          messages.add('The message was not sent.');
        default:
          break;
      }
    }
    return messages;
  }

  static String _settled(AgentChatTurnOutcome outcome) => switch (outcome) {
    AgentChatTurnOutcome.succeeded ||
    AgentChatTurnOutcome.running => 'The agent finished.',
    AgentChatTurnOutcome.failed => 'The turn failed.',
    AgentChatTurnOutcome.cancelled => 'The turn was cancelled.',
    AgentChatTurnOutcome.stopped => 'The turn stopped.',
    AgentChatTurnOutcome.interruptedByRestart =>
      'The turn was interrupted when the runtime restarted.',
  };
}
