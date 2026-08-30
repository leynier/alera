import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_canvas/application/agent_canvas_providers.dart';
import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/application/keyboard_command_dispatcher.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_drop_target.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_workspace_file_opener.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/features/workbench/domain/terminal_toolbar_placement.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_controller.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_overlay.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface_toolbar.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'terminal_surface_states.dart';

class TerminalSurface extends ConsumerStatefulWidget {
  const TerminalSurface({
    super.key,
    required this.session,
    this.autofocus = false,
  });

  final TerminalSessionHandle session;
  final bool autofocus;

  @override
  ConsumerState<TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends ConsumerState<TerminalSurface> {
  TerminalVisibilityLease? _visibilityLease;
  bool _refreshing = false;
  int _refreshGeneration = 0;
  late bool _composerVisible;

  @override
  void initState() {
    super.initState();
    _visibilityLease = widget.session.acquireVisibility();
    _attachComposer(widget.session);
    _scheduleStart(widget.session);
  }

  @override
  void didUpdateWidget(TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      _refreshGeneration += 1;
      _refreshing = false;
      _visibilityLease?.dispose();
      _visibilityLease = widget.session.acquireVisibility();
      _detachComposer(oldWidget.session);
      _attachComposer(widget.session);
      _scheduleStart(widget.session);
    }
  }

  @override
  void dispose() {
    _visibilityLease?.dispose();
    _visibilityLease = null;
    _detachComposer(widget.session);
    super.dispose();
  }

  void _attachComposer(TerminalSessionHandle session) {
    _composerVisible = session.composerController.visible;
    session.composerController.addListener(_handleComposerChanged);
  }

  void _detachComposer(TerminalSessionHandle session) {
    session.composerController.removeListener(_handleComposerChanged);
  }

  void _handleComposerChanged() {
    final visible = widget.session.composerController.visible;
    if (visible == _composerVisible) {
      return;
    }
    _composerVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.session.composerController.visible != visible) {
        return;
      }
      if (visible) {
        widget.session.composerController.focusNode.requestFocus();
      } else {
        widget.session.requestFocus();
      }
    });
  }

  void _scheduleStart(TerminalSessionHandle session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.session != session) {
        return;
      }
      unawaited(session.ensureStarted());
    });
  }

  Future<void> _refreshTerminal() async {
    if (_refreshing) {
      return;
    }
    final generation = ++_refreshGeneration;
    setState(() => _refreshing = true);
    try {
      await widget.session.refreshRendering();
    } finally {
      if (mounted && generation == _refreshGeneration) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// Intercepts Alera shortcuts before the key reaches the PTY. Returning
  /// `handled` swallows the key; `ignored` lets the terminal/shell receive it.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = ref.read(settingsControllerProvider).keyboard;
    final resolver = KeybindingResolver(settings: keyboard);
    final modifiers = KeyModifierState.fromKeyboard(HardwareKeyboard.instance);
    final resolved = resolver.resolveAction(event, modifiers);
    if (resolved == null) {
      return KeyEventResult.ignored;
    }
    // Under terminal-first, defer everything except bindings explicitly marked
    // as safe to intercept while a terminal is focused.
    if (keyboard.terminalPolicy == TerminalShortcutPolicy.terminalFirst &&
        !resolved.allowInTerminal) {
      return KeyEventResult.ignored;
    }
    KeyboardCommandDispatcher(
      ref: ref,
      context: context,
      terminalSession: widget.session,
    ).dispatch(resolved.id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the surface usable in isolated previews and test harnesses that do
    // not mount the application ProviderScope. The canvas catalog is
    // unavailable there, while the normal app still watches it.
    final hasProviderScope = _hasProviderScope(context);
    final hasCanvas =
        hasProviderScope &&
        ref
                .watch(agentCanvasesProvider(widget.session.workspaceId))
                .asData
                ?.value
                .isNotEmpty ==
            true;
    final toolbarCorner = hasProviderScope
        ? ref.watch(
            settingsControllerProvider.select(
              (settings) => settings.terminal.toolbarCorner,
            ),
          )
        : TerminalToolbarCorner.topRight;
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.session,
        widget.session.composerController,
      ]),
      builder: (context, _) => _buildSurface(
        context,
        hasCanvas: hasCanvas,
        toolbarCorner: toolbarCorner,
        canPersistToolbarCorner: hasProviderScope,
      ),
    );
  }

  Widget _buildSurface(
    BuildContext context, {
    required bool hasCanvas,
    required TerminalToolbarCorner toolbarCorner,
    required bool canPersistToolbarCorner,
  }) {
    final error = switch (widget.session.errorMessage) {
      final String message when message.trim().isNotEmpty => message,
      _ => null,
    };
    final operation = error == null ? widget.session.operation : null;
    final searchController = widget.session.searchController;
    return DropTarget(
      enable: error == null,
      onDragDone: (details) {
        handleTerminalFileDrop(
          session: widget.session,
          paths: details.files.map((file) => file.path),
          globalPosition: details.globalPosition,
        );
      },
      child: DragTarget<TerminalPathDragPayload>(
        onWillAcceptWithDetails: (_) => error == null,
        onAcceptWithDetails: (details) {
          handleTerminalPathDrop(
            session: widget.session,
            paths: details.data.paths,
          );
        },
        builder: (context, _, _) => _buildSurfaceContent(
          context,
          error: error,
          operation: operation,
          searchController: searchController,
          hasCanvas: hasCanvas,
          toolbarCorner: toolbarCorner,
          canPersistToolbarCorner: canPersistToolbarCorner,
        ),
      ),
    );
  }

  Widget _buildSurfaceContent(
    BuildContext context, {
    required String? error,
    required TerminalSessionOperation? operation,
    required TerminalSearchController? searchController,
    required bool hasCanvas,
    required TerminalToolbarCorner toolbarCorner,
    required bool canPersistToolbarCorner,
  }) {
    return Column(
      children: <Widget>[
        Expanded(
          child: _buildTerminalViewport(
            context,
            error: error,
            operation: operation,
            searchController: searchController,
            hasCanvas: hasCanvas,
            toolbarCorner: toolbarCorner,
            canPersistToolbarCorner: canPersistToolbarCorner,
          ),
        ),
        if (widget.session.composerController.visible)
          buildTerminalComposerForWorkspace(ref, widget.session),
      ],
    );
  }

  Widget _buildTerminalViewport(
    BuildContext context, {
    required String? error,
    required TerminalSessionOperation? operation,
    required TerminalSearchController? searchController,
    required bool hasCanvas,
    required TerminalToolbarCorner toolbarCorner,
    required bool canPersistToolbarCorner,
  }) {
    final toolbarButtonCount = terminalToolbarButtonCount(
      supportsPulse: widget.session.supportsTerminalPulse,
      hasCanvas: hasCanvas,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: <Widget>[
            Positioned.fill(child: _buildTerminalContent(context, error)),
            if (operation != null)
              Positioned.fill(
                child: _TerminalOperationState(operation: operation),
              ),
            if (error == null) _buildRestoreOverlay(),
            TerminalSurfaceToolbar(
              session: widget.session,
              viewportSize: constraints.biggest,
              corner: toolbarCorner,
              hasCanvas: hasCanvas,
              refreshing: _refreshing,
              onRefresh: () => unawaited(_refreshTerminal()),
              onShowAgentCanvas: _showAgentCanvas,
              onCornerChanged: canPersistToolbarCorner
                  ? _persistToolbarCorner
                  : null,
            ),
            if (searchController?.isOpen == true)
              _buildSearchOverlay(
                searchController!,
                toolbarCorner,
                toolbarButtonCount,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalContent(BuildContext context, String? error) {
    if (error != null) {
      return _TerminalErrorState(
        message: error,
        onReconnect: widget.session.reconnect,
        onRestart: widget.session.canRestart
            ? () => _confirmRestart(context)
            : null,
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: widget.session.buildView(
        autofocus: widget.autofocus,
        onKeyEvent: _handleTerminalKey,
      ),
    );
  }

  Widget _buildRestoreOverlay() {
    // Restoring an evicted terminal replays its whole scrollback over several
    // frames, so cover the area until the history is back.
    return Positioned.fill(
      child: ValueListenableBuilder<TerminalRestoreProgress?>(
        valueListenable: widget.session.restoreProgress,
        builder: (context, progress, _) {
          if (progress == null) {
            return const SizedBox.shrink();
          }
          return _TerminalRestoreState(progress: progress);
        },
      ),
    );
  }

  Widget _buildSearchOverlay(
    TerminalSearchController searchController,
    TerminalToolbarCorner toolbarCorner,
    int toolbarButtonCount,
  ) {
    final layout = terminalSearchOverlayLayout(
      toolbarCorner: toolbarCorner,
      toolbarButtonCount: toolbarButtonCount,
    );
    return Positioned(
      top: AleraTokens.space4,
      left: layout.left,
      right: layout.right,
      child: Align(
        alignment: layout.alignLeft ? Alignment.topLeft : Alignment.topRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.dialogWideWidth,
          ),
          child: TerminalSearchOverlay(
            controller: searchController,
            onClose: _closeSearch,
          ),
        ),
      ),
    );
  }

  void _persistToolbarCorner(TerminalToolbarCorner corner) {
    final terminal = ref.read(settingsControllerProvider).terminal;
    if (terminal.toolbarCorner == corner) {
      return;
    }
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .updateTerminal(
            (terminal) => terminal.copyWith(toolbarCorner: corner),
          ),
    );
  }

  void _showAgentCanvas() {
    final terminalSessionId = widget.session.terminalSessionId;
    if (terminalSessionId != null) {
      ref
          .read(
            agentCanvasSelectionProvider(widget.session.workspaceId).notifier,
          )
          .select(terminalSessionId);
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    controller.setContextPanelTab(WorkbenchContextPanelTab.agentCanvas);
    if (!ref.read(workbenchControllerProvider).viewPrefs.rightSidebarVisible) {
      controller.toggleRightSidebarVisible();
    }
  }

  void _closeSearch() {
    widget.session.closeSearch();
    widget.session.requestFocus();
  }

  bool _hasProviderScope(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Restart Terminal?'),
          content: const Text(
            'This will stop the current process tree and start a new shell. Terminal history will be preserved.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Restart Terminal'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await widget.session.restart();
    }
  }
}
