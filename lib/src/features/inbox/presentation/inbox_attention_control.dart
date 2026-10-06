import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/inbox/application/inbox_navigation.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status bar entry to the inbox with the count of unread replies. Hidden
/// when the runtime cannot answer inbox requests.
class InboxAttentionControl extends ConsumerWidget {
  const InboxAttentionControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(inboxUnreadReplyCountProvider);
    if (count == null) return const SizedBox.shrink();
    final label = count == 0
        ? 'Open Inbox'
        : 'Open Inbox · $count Unread ${count == 1 ? 'Reply' : 'Replies'}';
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: () => ref.read(inboxNavigationProvider.notifier).open(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(AleraIcons.inbox, size: AleraTokens.iconSm),
              const SizedBox(width: AleraTokens.space4),
              Text(
                count > 999 ? '999+' : '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: count > 0
                      ? AleraTokens.accent
                      : AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
