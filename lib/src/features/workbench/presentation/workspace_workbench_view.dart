import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface.dart';
import 'package:flutter/material.dart';

class WorkspaceWorkbenchView extends StatelessWidget {
  const WorkspaceWorkbenchView({
    super.key,
    required this.project,
    required this.workspace,
    required this.tabs,
    required this.activeTab,
    required this.terminalRuntime,
    required this.onCreateTab,
    required this.onSelectTab,
    required this.onCloseTab,
  });

  final Project project;
  final Workspace workspace;
  final List<TerminalTabRecord> tabs;
  final TerminalTabRecord? activeTab;
  final TerminalRuntime terminalRuntime;
  final VoidCallback onCreateTab;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;

  @override
  Widget build(BuildContext context) {
    final activeTab = this.activeTab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _TerminalTabStrip(
          workspace: workspace,
          tabs: tabs,
          activeTabId: activeTab?.id,
          terminalRuntime: terminalRuntime,
          onSelectTab: onSelectTab,
          onCloseTab: onCloseTab,
          onCreateTab: onCreateTab,
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: activeTab == null
              ? const Center(child: CircularProgressIndicator())
              : TerminalSurface(
                  session: terminalRuntime.sessionFor(
                    workspace: workspace,
                    tab: activeTab,
                  ),
                  autofocus: true,
                ),
        ),
      ],
    );
  }
}

class _TerminalTabStrip extends StatefulWidget {
  const _TerminalTabStrip({
    required this.workspace,
    required this.tabs,
    required this.activeTabId,
    required this.terminalRuntime,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCreateTab,
  });

  final Workspace workspace;
  final List<TerminalTabRecord> tabs;
  final String? activeTabId;
  final TerminalRuntime terminalRuntime;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onCreateTab;

  @override
  State<_TerminalTabStrip> createState() => _TerminalTabStripState();
}

class _TerminalTabStripState extends State<_TerminalTabStrip> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final overflow = _scrollController.position.maxScrollExtent > 0.5;
    if (overflow != _hasOverflow) {
      setState(() => _hasOverflow = overflow);
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
    final addButton = _NewTerminalButton(onPressed: widget.onCreateTab);
    return ColoredBox(
      color: AleraTokens.surface,
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                  vertical: AleraTokens.space6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final tab in widget.tabs)
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AleraTokens.space8,
                        ),
                        child: _TerminalTabChip(
                          session: widget.terminalRuntime.sessionFor(
                            workspace: widget.workspace,
                            tab: tab,
                          ),
                          active: tab.id == widget.activeTabId,
                          onTap: () => widget.onSelectTab(tab.id),
                          onClose: () => widget.onCloseTab(tab.id),
                        ),
                      ),
                    if (!_hasOverflow) addButton,
                  ],
                ),
              ),
            ),
            if (_hasOverflow)
              Padding(
                padding: const EdgeInsets.only(right: AleraTokens.space8),
                child: addButton,
              ),
          ],
        ),
      ),
    );
  }
}

class _NewTerminalButton extends StatelessWidget {
  const _NewTerminalButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      iconSize: 16,
      tooltip: 'New terminal',
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(28),
        maximumSize: const Size.square(28),
        foregroundColor: AleraTokens.foregroundMuted,
        hoverColor: AleraTokens.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        ),
      ),
    );
  }
}

class _TerminalTabChip extends StatelessWidget {
  const _TerminalTabChip({
    required this.session,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final TerminalSessionHandle session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return Material(
          color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            child: Container(
              constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                border: Border.all(
                  color: active ? AleraTokens.border : AleraTokens.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.terminal,
                    size: 12,
                    color: active
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      session.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: active
                            ? AleraTokens.foreground
                            : AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                  InkWell(
                    onTap: onClose,
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
