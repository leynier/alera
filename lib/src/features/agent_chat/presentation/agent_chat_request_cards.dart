import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_elicitation_form.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// An approval the agent is blocked on: what it wants to run, change or read,
/// and the decisions the runtime offers, in the runtime's order, since a
/// provider may not honor any other.
class const AgentChatApprovalCard({
  super.key,
  required final AgentChatRequest request,
  required final bool responding,
  required final bool enabled,
  required final ValueChanged<AgentChatApprovalDecision> onDecision,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final command = agentChatJsonString(request.command);
    final cwd = agentChatJsonString(request.cwd);
    final path = agentChatJsonString(request.path);
    final detail = agentChatJsonString(request.detail);
    final expiresAt = request.expiresAt;
    return _RequestCardFrame(
      title: agentChatJsonString(request.title) ?? _approvalTitle(request.kind),
      responding: responding,
      actions: _decisionButtons(
        request.offeredDecisions,
        enabled: enabled && !responding,
        onDecision: onDecision,
      ),
      children: <Widget>[
        ?_CappedBody.of(<Widget>[
          if (command != null) _MonoBlock(text: command),
          if (cwd != null)
            AleraKeyValueRow(label: 'Directory', value: cwd, monospace: true),
          if (path != null)
            AleraKeyValueRow(label: 'Path', value: path, monospace: true),
          if (detail != null)
            SelectableText(detail, style: theme.textTheme.bodyMedium),
        ]),
        if (expiresAt != null)
          Text(
            'Expires at ${_clockTime(context, expiresAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
      ],
    );
  }
}

/// Input an MCP server asked for through the agent: a flat form, a link to
/// open, or a plain confirmation. A form with fields Alera cannot render is
/// explained instead, and only Decline and Cancel are offered for it.
class const AgentChatElicitationCard({
  super.key,
  required final AgentChatRequest request,
  required final bool responding,
  required final bool enabled,
  required final void Function(
    AgentChatElicitationAction action,
    Map<String, Object?>? content,
  )
  onRespond,
  final ValueChanged<String>? onOpenUrl,
}) extends StatefulWidget {
  @override
  State<AgentChatElicitationCard> createState() =>
      _AgentChatElicitationCardState();
}

class _AgentChatElicitationCardState extends State<AgentChatElicitationCard> {
  late AgentChatElicitationForm _form = AgentChatElicitationForm(
    widget.request.elicitation,
  );

  @override
  void didUpdateWidget(covariant AgentChatElicitationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.id == widget.request.id) return;
    _form.dispose();
    _form = AgentChatElicitationForm(widget.request.elicitation);
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _accept(_ElicitationShape shape) =>
      widget.onRespond(.accept, switch (shape) {
        .form => _form.content(),
        .confirmation => const <String, Object?>{},
        _ => null,
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elicitation = widget.request.elicitation;
    final shape = _shapeOf(elicitation);
    final canRespond = widget.enabled && !widget.responding;
    final message = elicitation?.message.trim() ?? '';
    final url = elicitation?.url;
    final open = widget.onOpenUrl;
    final canAccept = switch (shape) {
      .form => _form.isValid,
      .link || .confirmation => true,
      .unsupported => false,
    };
    return _RequestCardFrame(
      title: agentChatJsonString(widget.request.title) ?? 'Input Requested',
      responding: widget.responding,
      actions: <Widget>[
        if (shape != .unsupported)
          FilledButton(
            onPressed: canRespond && canAccept ? () => _accept(shape) : null,
            child: const Text('Accept'),
          ),
        TextButton(
          onPressed: canRespond ? () => widget.onRespond(.decline, null) : null,
          child: const Text('Decline'),
        ),
        TextButton(
          onPressed: canRespond ? () => widget.onRespond(.cancel, null) : null,
          child: const Text('Cancel'),
        ),
      ],
      children: <Widget>[
        ?_CappedBody.of(<Widget>[
          if (message.isNotEmpty)
            SelectableText(message, style: theme.textTheme.bodyMedium),
          if (shape == .form)
            AgentChatElicitationFields(
              form: _form,
              enabled: canRespond,
              onChanged: () => setState(() {}),
            ),
          if (shape == .link && url != null) ...<Widget>[
            _MonoBlock(text: url),
            // Only web links: the server chooses this URL, and other schemes
            // can launch local apps.
            if (open != null && _isWebUrl(url))
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => open(url),
                  icon: const Icon(
                    AleraIcons.external,
                    size: AleraTokens.iconMd,
                  ),
                  label: const Text('Open Link'),
                ),
              ),
          ],
          if (shape == .unsupported)
            const AleraInlineNotice(
              tone: .warning,
              message:
                  'This form cannot be filled in here. Decline or cancel it '
                  'instead.',
            ),
        ]),
      ],
    );
  }
}

/// A request Alera cannot answer, such as a client tool call or a credential
/// refresh. Any decisions the runtime does list are still offered.
class const AgentChatUnsupportedRequestCard({
  super.key,
  required final AgentChatRequest request,
  required final bool responding,
  required final bool enabled,
  required final ValueChanged<AgentChatApprovalDecision> onDecision,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = agentChatJsonString(request.detail);
    return _RequestCardFrame(
      title: agentChatJsonString(request.title) ?? 'The Agent Is Waiting',
      responding: responding,
      actions: _decisionButtons(
        request.decisions,
        enabled: enabled && !responding,
        onDecision: onDecision,
      ),
      children: <Widget>[
        ?_CappedBody.of(<Widget>[
          if (detail != null)
            SelectableText(detail, style: theme.textTheme.bodyMedium),
        ]),
        Text(
          "Alera cannot answer this type of request. Answer it from the "
          "agent's own client, or stop the turn to continue.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );
  }
}

enum _ElicitationShape { form, link, confirmation, unsupported }

_ElicitationShape _shapeOf(AgentChatElicitation? elicitation) {
  if (elicitation == null) return .unsupported;
  if (elicitation.url != null) return .link;
  if (agentChatWireToken(elicitation.mode) == 'url') return .unsupported;
  if (elicitation.hasSupportedForm) return .form;
  // A form without fields only asks the user to confirm.
  return elicitation.properties.isEmpty ? .confirmation : .unsupported;
}

bool _isWebUrl(String url) {
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  return scheme == 'https' || scheme == 'http';
}

String _approvalTitle(AgentChatRequestKind kind) => switch (kind) {
  .commandExecutionApproval || .execCommandApproval => 'Run Command?',
  .fileChangeApproval || .applyPatchApproval => 'Apply File Changes?',
  .fileReadApproval => 'Read File?',
  .permissionApproval => 'Permission Request',
  _ => 'Approval Required',
};

String _decisionLabel(AgentChatApprovalDecision decision) => switch (decision) {
  .accept => 'Allow Once',
  .acceptForSession => 'Allow For Session',
  .acceptAlways => 'Always Allow',
  .decline => 'Decline',
  .cancel => 'Cancel Turn',
};

List<Widget> _decisionButtons(
  List<AgentChatApprovalDecision> decisions, {
  required bool enabled,
  required ValueChanged<AgentChatApprovalDecision> onDecision,
}) => <Widget>[
  for (final decision in decisions)
    if (decision == .accept)
      FilledButton(
        onPressed: enabled ? () => onDecision(decision) : null,
        child: Text(_decisionLabel(decision)),
      )
    else
      TextButton(
        onPressed: enabled ? () => onDecision(decision) : null,
        child: Text(_decisionLabel(decision)),
      ),
];

String _clockTime(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value.toLocal()),
      alwaysUse24HourFormat: true,
    );

class const _RequestCardFrame({
  required final String title,
  required final bool responding,
  required final List<Widget> children,
  required final List<Widget> actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Material surface rather than a decorated box, so the ink of the
    // checkboxes and fields inside paints above the card color.
    return Material(
      color: AleraTokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space8,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                ),
                if (responding) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  const SizedBox.square(
                    dimension: AleraTokens.iconMd,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  ),
                ],
              ],
            ),
            ...children,
            if (actions.isNotEmpty)
              Wrap(
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                children: actions,
              ),
          ],
        ),
      ),
    );
  }
}

/// Request details in a scroll area capped at
/// [AleraTokens.agentChatRequestMaxHeight].
class const _CappedBody({required final List<Widget> children})
    extends StatelessWidget {
  /// Null when there is nothing to show, so the card leaves no gap for it.
  static Widget? of(List<Widget> children) =>
      children.isEmpty ? null : _CappedBody(children: children);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AleraTokens.agentChatRequestMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space8,
          children: children,
        ),
      ),
    );
  }
}

class const _MonoBlock({required final String text}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: SelectableText(
        text,
        style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
      ),
    );
  }
}
