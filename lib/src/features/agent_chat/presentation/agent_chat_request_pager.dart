import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// "Request 2 of 3" with previous and next, above the docked request.
class const AgentChatRequestPager({
  super.key,
  required final int index,
  required final int count,
  required final ValueChanged<int> onSelect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        mainAxisAlignment: .end,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              'Request ${index + 1} of $count',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          AleraIconButton(
            tooltip: 'Previous Request',
            icon: AleraIcons.chevronLeft,
            minSize: AleraTokens.iconButtonSm,
            onPressed: index > 0 ? () => onSelect(index - 1) : null,
          ),
          AleraIconButton(
            tooltip: 'Next Request',
            icon: AleraIcons.chevronRight,
            minSize: AleraTokens.iconButtonSm,
            onPressed: index < count - 1 ? () => onSelect(index + 1) : null,
          ),
        ],
      ),
    );
  }
}
