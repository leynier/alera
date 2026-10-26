import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

const double _cardWidth = 320;

/// T3 Code's thread hover card on a row that already handles its own taps:
/// [preview] appears after a short hover over [child] and stays while the
/// pointer is on it. A null [preview] leaves [child] alone.
class const AgentChatPreviewHover({
  super.key,
  required final AgentChatPreview? preview,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final preview = this.preview;
    if (preview == null) return child;
    return AleraHoverCard(
      semanticsLabel: preview.title,
      pinOnTap: false,
      card: AgentChatPreviewCard(preview: preview),
      child: child,
    );
  }
}

/// A preview's title over its metadata lines, in the floating card style.
class const AgentChatPreviewCard({
  super.key,
  required final AgentChatPreview preview,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('agent-chat-preview-card'),
      width: _cardWidth,
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            preview.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AleraTokens.foreground,
            ),
          ),
          for (final line in preview.lines) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            _Line(line: line),
          ],
        ],
      ),
    );
  }
}

class const _Line({required final AgentChatPreviewLine line})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = agentChatPreviewToneColor(line.tone);
    final glyph = switch (line.glyph) {
      AgentChatPreviewGlyph.provider => AgentChatProviderIcon(
        provider: line.provider ?? '',
        color: color,
      ),
      final glyph => Icon(
        agentChatPreviewGlyphIcon(glyph, line.tone),
        size: AleraTokens.iconSm,
        color: color,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: AleraTokens.space2),
          child: glyph,
        ),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: Text(
            line.text,
            maxLines: line.glyph == AgentChatPreviewGlyph.summary ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The icon a preview line leads with, by glyph and tone.
IconData agentChatPreviewGlyphIcon(
  AgentChatPreviewGlyph glyph,
  AgentChatPreviewTone tone,
) => switch (glyph) {
  AgentChatPreviewGlyph.provider => AleraIcons.agent,
  AgentChatPreviewGlyph.status => switch (tone) {
    AgentChatPreviewTone.working => AleraIcons.loading,
    AgentChatPreviewTone.success => AleraIcons.success,
    AgentChatPreviewTone.error => AleraIcons.error,
    _ => AleraIcons.circle,
  },
  AgentChatPreviewGlyph.relation => AleraIcons.gitFork,
  AgentChatPreviewGlyph.time => AleraIcons.time,
  AgentChatPreviewGlyph.transfer => AleraIcons.gitMerge,
  AgentChatPreviewGlyph.summary => AleraIcons.text,
};

Color agentChatPreviewToneColor(AgentChatPreviewTone tone) => switch (tone) {
  AgentChatPreviewTone.normal => AleraTokens.foreground,
  AgentChatPreviewTone.working => AleraTokens.info,
  AgentChatPreviewTone.success => AleraTokens.success,
  AgentChatPreviewTone.error => AleraTokens.error,
  AgentChatPreviewTone.muted => AleraTokens.foregroundMuted,
};
