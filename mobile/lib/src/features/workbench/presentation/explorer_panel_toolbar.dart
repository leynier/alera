import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

/// Explorer view actions. Same glyphs and tooltips as the desktop explorer
/// toolbar, without its file-mutation buttons.
class const ExplorerPanelToolbar({
  super.key,
  required final String title,
  required final bool hideIgnored,
  required final bool refreshing,
  required final bool canCollapse,
  required final VoidCallback onToggleIgnored,
  required final VoidCallback onCollapseAll,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AleraTokens.space16,
          right: AleraTokens.space4,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: .ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            AleraIconButton(
              tooltip: hideIgnored
                  ? 'Show Ignored Files'
                  : 'Hide Ignored Files',
              onPressed: refreshing ? null : onToggleIgnored,
              icon: hideIgnored ? AleraIcons.hidden : AleraIcons.visible,
            ),
            AleraIconButton(
              tooltip: 'Collapse All',
              onPressed: canCollapse ? onCollapseAll : null,
              icon: AleraIcons.collapseAll,
            ),
            AleraIconButton(
              tooltip: 'Refresh',
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing ? AleraIcons.loading : AleraIcons.refresh,
            ),
          ],
        ),
      ),
    );
  }
}
