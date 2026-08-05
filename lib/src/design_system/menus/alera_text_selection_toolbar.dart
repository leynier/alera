import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_menu_item.dart';
import 'package:flutter/material.dart';

/// Alera-styled text selection menu on pointer platforms.
///
/// Touch platforms keep Flutter's adaptive toolbar so their native selection
/// behavior and geometry remain unchanged.
class AleraTextSelectionToolbar extends StatelessWidget {
  const AleraTextSelectionToolbar({
    super.key,
    required this.anchors,
    required this.buttonItems,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;

  static Widget editableText(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return AleraTextSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: editableTextState.contextMenuButtonItems,
    );
  }

  static Widget selectableRegion(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AleraTextSelectionToolbar(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: selectableRegionState.contextMenuButtonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!_usesPointerMenu(Theme.of(context).platform)) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: buttonItems,
      );
    }

    final screenPadding =
        MediaQuery.paddingOf(context).top + AleraTokens.space8;
    final localAdjustment = Offset(AleraTokens.space8, screenPadding);
    final popupTheme = Theme.of(context).popupMenuTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AleraTokens.space8,
        screenPadding,
        AleraTokens.space8,
        AleraTokens.space8,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchors.primaryAnchor - localAdjustment,
        ),
        child: SizedBox(
          width: AleraTokens.contextMenuWidth,
          child: Material(
            color: AleraTokens.surface,
            elevation: popupTheme.elevation ?? 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              side: const BorderSide(color: AleraTokens.border),
            ),
            child: Padding(
              padding:
                  popupTheme.menuPadding ??
                  const EdgeInsets.all(AleraTokens.space12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final item in buttonItems)
                    AleraDropdownMenuItem(
                      label: AdaptiveTextSelectionToolbar.getButtonLabel(
                        context,
                        item,
                      ),
                      onTap: item.onPressed,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool _usesPointerMenu(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
    };
  }
}
