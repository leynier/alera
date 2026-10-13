part of 'welcome_dashboard.dart';

class const HomeComposerMenuChoice({
  required final String value,
  required final String label,
  final Widget? leading,
  final bool selected = false,
  final bool enabled = true,
});

Future<String?> showHomeComposerMenu({
  required BuildContext context,
  required List<HomeComposerMenuChoice> choices,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return showDialog<String>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final width = size.width < AleraTokens.workspaceDetailsWidth
            ? size.width - AleraTokens.space16
            : AleraTokens.workspaceDetailsWidth;
        final below = size.height - anchor.bottom - AleraTokens.space8;
        final above = anchor.top - AleraTokens.space8;
        final opensDown = below >= above;
        return Stack(
          children: [
            Positioned(
              left: anchor.left.clamp(
                AleraTokens.space8,
                size.width - width - AleraTokens.space8,
              ),
              top: opensDown ? anchor.bottom + AleraTokens.space4 : null,
              bottom: opensDown
                  ? null
                  : size.height - anchor.top + AleraTokens.space4,
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: opensDown ? below : above,
                ),
                child: Material(
                  color: AleraTokens.surface,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    side: const BorderSide(color: AleraTokens.border),
                  ),
                  child: AleraDropdownFilterPopover<String>(
                    entries: [
                      for (final choice in choices)
                        AleraDropdownFieldEntry(
                          value: choice.value,
                          label: choice.label,
                          leading: choice.leading,
                          enabled: choice.enabled,
                        ),
                    ],
                    selectedValue: choices
                        .where((choice) => choice.selected)
                        .firstOrNull
                        ?.value,
                    filterHintText: 'Search',
                    onSelected: (value) => Navigator.of(context).pop(value),
                    onDismiss: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
