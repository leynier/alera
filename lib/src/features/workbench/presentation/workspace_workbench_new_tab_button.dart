part of 'workspace_workbench_view.dart';

enum _NewTabMenuAction { terminal, codex, browser, mobileEmulator }

class const _NewTabButton({
  required final String groupId,
  required final VoidCallback onCreateTab,
  required final VoidCallback? onCreateBrowserTab,
  required final VoidCallback? onCreateCodexTab,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final onOpenMobileEmulator = _MobileEmulatorOpenScope.maybeOf(context);
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_NewTabMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_NewTabMenuAction>>[
        const AleraDropdownEntry<_NewTabMenuAction>(
          value: .terminal,
          label: 'New Terminal',
          leading: Icon(
            AleraIcons.terminal,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
        ),
        if (onCreateCodexTab != null)
          const AleraDropdownEntry<_NewTabMenuAction>(
            value: .codex,
            label: 'New Codex Chat',
            leading: ExcludeSemantics(
              child: AgentIdentityIcon(
                key: ValueKey<String>('new-tab-codex-icon'),
                agentType: .codex,
                size: 16,
                color: AleraTokens.foregroundMuted,
                showTooltip: false,
              ),
            ),
          ),
        if (onCreateBrowserTab != null)
          const AleraDropdownEntry<_NewTabMenuAction>(
            value: .browser,
            label: 'New Browser Tab',
            leading: Icon(
              AleraIcons.public,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        AleraDropdownEntry<_NewTabMenuAction>(
          value: .mobileEmulator,
          label: 'New Mobile Emulator',
          enabled: onOpenMobileEmulator != null,
          leading: const Icon(
            AleraIcons.mobileDevice,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
    );

    if (selected == null) {
      return;
    }

    switch (selected) {
      case _NewTabMenuAction.terminal:
        onCreateTab();
      case _NewTabMenuAction.codex:
        onCreateCodexTab?.call();
      case _NewTabMenuAction.browser:
        onCreateBrowserTab?.call();
      case _NewTabMenuAction.mobileEmulator:
        final open = onOpenMobileEmulator;
        if (open != null) {
          unawaited(open(targetGroupId: groupId));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'New Tab',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: () => unawaited(_openMenu(context)),
    );
  }
}
