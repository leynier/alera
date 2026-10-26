import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The phone's stand-in for the desktop hover card: a long press on a
/// lineage, sub-agent or transfer row shows the same preview in a sheet,
/// since a touch screen has no hover. The press itself keeps its action.
void showAgentChatPreviewSheet(BuildContext context, AgentChatPreview preview) {
  unawaited(HapticFeedback.selectionClick());
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => AgentChatPreviewSheet(preview: preview),
    ),
  );
}

/// A provider's readable name for preview lines.
String agentChatPreviewProviderLabel(String provider) =>
    switch (agentChatProviderName(provider)) {
      'the agent' => 'Agent',
      final name => name,
    };

class const AgentChatPreviewSheet({
  super.key,
  required final AgentChatPreview preview,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey<String>('agent-chat-preview-sheet'),
      shrinkWrap: true,
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: <Widget>[
        Text(preview.title, style: theme.textTheme.titleMedium),
        for (final line in preview.lines) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Row(
            crossAxisAlignment: .start,
            children: <Widget>[
              _Glyph(line: line),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  line.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _toneColor(line.tone),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class const _Glyph({required final AgentChatPreviewLine line})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = _toneColor(line.tone);
    if (line.glyph == AgentChatPreviewGlyph.provider &&
        (line.provider ?? '').isNotEmpty) {
      return AgentIdentityIcon(
        agentType: agentChatAgentType(line.provider!),
        size: AleraTokens.space16,
        showTooltip: false,
      );
    }
    final icon = switch (line.glyph) {
      AgentChatPreviewGlyph.provider => AleraIcons.agent,
      AgentChatPreviewGlyph.status => switch (line.tone) {
        AgentChatPreviewTone.working => AleraIcons.loading,
        AgentChatPreviewTone.success => AleraIcons.success,
        AgentChatPreviewTone.error => AleraIcons.warning,
        _ => AleraIcons.circle,
      },
      AgentChatPreviewGlyph.relation => AleraIcons.gitFork,
      AgentChatPreviewGlyph.time => AleraIcons.time,
      AgentChatPreviewGlyph.transfer => AleraIcons.gitMerge,
      AgentChatPreviewGlyph.summary => AleraIcons.textOnly,
    };
    return Icon(icon, size: AleraTokens.space16, color: color);
  }
}

Color _toneColor(AgentChatPreviewTone tone) => switch (tone) {
  AgentChatPreviewTone.normal => AleraTokens.foreground,
  AgentChatPreviewTone.working => AleraTokens.info,
  AgentChatPreviewTone.success => AleraTokens.success,
  AgentChatPreviewTone.error => AleraTokens.error,
  AgentChatPreviewTone.muted => AleraTokens.foregroundMuted,
};
