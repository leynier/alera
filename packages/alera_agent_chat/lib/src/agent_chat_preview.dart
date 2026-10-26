import 'package:alera_agent_chat/src/agent_chat_context_transfer.dart';
import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_subagent.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';
import 'package:alera_agent_chat/src/agent_chat_timeline_projection.dart';

/// The glyph a preview line leads with; each app maps it to its icon set.
enum AgentChatPreviewGlyph {
  /// The provider's mark; the line's [AgentChatPreviewLine.provider] names it.
  provider,
  status,
  relation,
  time,
  transfer,
  summary,
}

enum AgentChatPreviewTone { normal, working, success, error, muted }

/// One metadata line of a preview card.
final class const AgentChatPreviewLine({
  required final AgentChatPreviewGlyph glyph,
  required final String text,
  final AgentChatPreviewTone tone = AgentChatPreviewTone.normal,
  final String? provider,
});

/// What T3 Code's thread hover card (`ThreadHoverCard`,
/// `SubagentTooltipContent`) shows about a chat, a sub-agent or a context
/// transfer: a title and a few metadata lines. Desktop shows it on hover,
/// the phone on long press, so both read the same lines from here.
/// [providerLabel] names a provider for the model line; [now] dates the
/// relative times.
final class const AgentChatPreview({
  required final String title,
  required final List<AgentChatPreviewLine> lines,
}) {
  /// A related chat: its agent, state and last activity. [relation] names
  /// how it relates to the chat on screen ("Fork", "Parent Chat").
  factory chat(
    AgentChatSummary? chat, {
    required String fallbackTitle,
    String? relation,
    String Function(String provider) providerLabel = _identity,
    DateTime? now,
  }) {
    final title = _firstText(<String?>[chat?.title], fallbackTitle);
    return AgentChatPreview(
      title: title,
      lines: <AgentChatPreviewLine>[
        if (relation != null)
          AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.relation,
            text: relation,
          ),
        if (chat == null)
          const AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.status,
            text: 'Unavailable on this device',
            tone: AgentChatPreviewTone.muted,
          )
        else ...<AgentChatPreviewLine>[
          _agent(chat.provider, chat.model, null, providerLabel),
          _chatStatus(chat),
          AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.time,
            text: 'Updated ${agentChatRelativeTime(chat.updatedAt, now)}',
            tone: AgentChatPreviewTone.muted,
          ),
        ],
      ],
    );
  }

  /// A provider-native sub-agent, as its call reports it: model and effort,
  /// a live or final status with its timing, and the latest summary.
  factory subagent(
    AgentChatItem call, {
    String provider = '',
    String Function(String provider) providerLabel = _identity,
    DateTime? now,
  }) {
    final status = call.subagentStatus;
    final summary = _oneLine(call.subagent?.summary ?? call.subagentPrompt);
    return AgentChatPreview(
      title: call.subagentLabel,
      lines: <AgentChatPreviewLine>[
        _agent(
          provider,
          call.subagentModel,
          call.subagentReasoningEffort,
          providerLabel,
        ),
        AgentChatPreviewLine(
          glyph: AgentChatPreviewGlyph.status,
          text: agentChatSubagentStatusLabel(call, now ?? DateTime.now()),
          tone: switch (status) {
            AgentChatSubagentStatus.running => AgentChatPreviewTone.working,
            AgentChatSubagentStatus.completed => AgentChatPreviewTone.success,
            AgentChatSubagentStatus.failed => AgentChatPreviewTone.error,
            AgentChatSubagentStatus.stopped => AgentChatPreviewTone.muted,
          },
        ),
        if (summary != null)
          AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.summary,
            text: summary,
            tone: AgentChatPreviewTone.muted,
          ),
      ],
    );
  }

  /// A context transfer into the chat on screen: how it came, from which
  /// chat and agent, and whether the receiving agent has it yet.
  factory transfer(
    AgentChatContextTransfer transfer, {
    required String sourceTitle,
    AgentChatSummary? source,
    String Function(String provider) providerLabel = _identity,
    DateTime? now,
  }) {
    final from = transfer.from;
    final to = transfer.to;
    String endpoint(AgentChatHandoffEndpoint endpoint) =>
        endpoint.model ?? providerLabel(endpoint.provider);
    return AgentChatPreview(
      title: sourceTitle,
      lines: <AgentChatPreviewLine>[
        AgentChatPreviewLine(
          glyph: AgentChatPreviewGlyph.transfer,
          text: '${transfer.kind.label} · ${transfer.statusLabel}',
          tone: transfer.failed
              ? AgentChatPreviewTone.error
              : transfer.status == AgentChatTransferStatus.pending
              ? AgentChatPreviewTone.working
              : AgentChatPreviewTone.normal,
        ),
        if (from != null && to != null && from.provider != to.provider)
          AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.provider,
            provider: to.provider,
            text: '${endpoint(from)} → ${endpoint(to)}',
          )
        else if (source != null)
          _agent(source.provider, source.model, null, providerLabel)
        else if (from != null)
          _agent(from.provider, from.model, null, providerLabel),
        if (transfer.error case final error?)
          AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.summary,
            text: error,
            tone: AgentChatPreviewTone.error,
          ),
        AgentChatPreviewLine(
          glyph: AgentChatPreviewGlyph.time,
          text: switch (transfer.consumedAt) {
            final at? => 'Delivered ${agentChatRelativeTime(at, now)}',
            null => 'Sent ${agentChatRelativeTime(transfer.createdAt, now)}',
          },
          tone: AgentChatPreviewTone.muted,
        ),
        if (source == null || source.archived)
          const AgentChatPreviewLine(
            glyph: AgentChatPreviewGlyph.status,
            text: 'Source chat unavailable',
            tone: AgentChatPreviewTone.muted,
          ),
      ],
    );
  }
}

String _identity(String provider) => provider;

AgentChatPreviewLine _agent(
  String provider,
  String? model,
  String? effort,
  String Function(String provider) providerLabel,
) {
  final label = provider.isEmpty ? '' : providerLabel(provider);
  final name = model == null || model.trim().isEmpty
      ? label
      : label.isEmpty || label == model
      ? model
      : '$model · $label';
  return AgentChatPreviewLine(
    glyph: AgentChatPreviewGlyph.provider,
    provider: provider,
    text: effort == null || effort.isEmpty ? name : '$name · $effort',
  );
}

AgentChatPreviewLine _chatStatus(AgentChatSummary chat) {
  final working =
      chat.busy ||
      chat.status == AgentChatSessionStatus.running ||
      chat.status == AgentChatSessionStatus.waiting;
  final (text, tone) = switch (chat) {
    _ when chat.archived => ('Archived', AgentChatPreviewTone.muted),
    _ when chat.pendingRequestCount > 0 => (
      'Needs Input',
      AgentChatPreviewTone.working,
    ),
    _ when working => ('Working', AgentChatPreviewTone.working),
    _ when chat.status == AgentChatSessionStatus.error => (
      'Failed',
      AgentChatPreviewTone.error,
    ),
    _ => ('Idle', AgentChatPreviewTone.muted),
  };
  return AgentChatPreviewLine(
    glyph: AgentChatPreviewGlyph.status,
    text: text,
    tone: tone,
  );
}

String _firstText(List<String?> candidates, String fallback) {
  for (final candidate in candidates) {
    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return fallback;
}

/// The first non-empty line of [text], bounded for a card.
String? _oneLine(String? text) {
  final line = text
      ?.split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (line == null || line.isEmpty) return null;
  return line.length <= 140 ? line : '${line.substring(0, 139)}…';
}

/// "just now", "5 min ago", "3 h ago", "2 d ago".
String agentChatRelativeTime(DateTime at, [DateTime? now]) {
  final age = (now ?? DateTime.now()).difference(at);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes} min ago';
  if (age.inDays < 1) return '${age.inHours} h ago';
  return '${age.inDays} d ago';
}
