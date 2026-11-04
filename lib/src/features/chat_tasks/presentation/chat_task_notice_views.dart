import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Who sent a message into this chat when it was another chat.
class const ChatMessageSenderRow({
  super.key,
  required final String senderTitle,
  final String? senderPlace,
  final VoidCallback? onOpenChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _OriginLine(
    label: <String>['From $senderTitle', ?senderPlace].join(' · '),
    actions: <Widget>[
      if (onOpenChat != null)
        TextButton(
          key: const ValueKey<String>('chatMessageSenderOpenChat'),
          onPressed: onOpenChat,
          child: const Text('Open Chat'),
        ),
    ],
  );
}

/// Where a task brief came from, in the child chat: `Delegated by Planner`
/// with Open Parent, or `Delegated by you` when a person owns the task.
class const ChatTaskOriginRow({
  super.key,
  required final String label,
  final String? place,
  final VoidCallback? onOpenParent,
  final VoidCallback? onView,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _OriginLine(
    key: const ValueKey<String>('chatTaskOrigin'),
    label: <String>[label, ?place].join(' · '),
    actions: <Widget>[
      if (onOpenParent != null)
        TextButton(
          key: const ValueKey<String>('chatTaskOriginOpenParent'),
          onPressed: onOpenParent,
          child: const Text('Open Parent'),
        ),
      if (onView != null)
        TextButton(
          key: const ValueKey<String>('chatTaskOriginView'),
          onPressed: onView,
          child: const Text('View In Activity'),
        ),
    ],
  );
}

class const _OriginLine({
  super.key,
  required final String label,
  required final List<Widget> actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(
        AleraIcons.agent,
        size: AleraTokens.iconSm,
        color: AleraTokens.foregroundMuted,
      ),
      const SizedBox(width: AleraTokens.space6),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: .ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
      ...actions,
    ],
  );
}
