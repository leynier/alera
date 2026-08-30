import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/agent_canvas/application/agent_canvas_providers.dart';
import 'package:alera/src/features/agent_canvas/domain/agent_canvas.dart';
import 'package:alera/src/features/agent_canvas/presentation/agent_surface_renderer.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_canvas_panel_widgets.dart';

typedef AgentCanvasFileOpener = Future<void> Function(String relativePath);
typedef AgentCanvasPathOpener = Future<void> Function(String relativePath);
typedef AgentCanvasTerminalFocuser = void Function(String terminalSessionId);
typedef AgentCanvasArtifactOpener = void Function(String artifactId);
typedef AgentCanvasSourceControlAction = Future<void> Function(
  String kind,
  Map<String, Object?> action,
);

class AgentCanvasPanel extends ConsumerStatefulWidget {
  const AgentCanvasPanel({
    super.key,
    required this.workspace,
    required this.onOpenFile,
    required this.onOpenDiff,
    required this.onFocusTerminal,
    required this.onOpenPullRequest,
    required this.onOpenArtifact,
    required this.onSwitchContextPanel,
    this.onSourceControlAction,
  });

  final Workspace workspace;
  final AgentCanvasFileOpener onOpenFile;
  final AgentCanvasPathOpener onOpenDiff;
  final AgentCanvasTerminalFocuser onFocusTerminal;
  final VoidCallback onOpenPullRequest;
  final AgentCanvasArtifactOpener onOpenArtifact;
  final ValueChanged<WorkbenchContextPanelTab> onSwitchContextPanel;
  final AgentCanvasSourceControlAction? onSourceControlAction;

  @override
  ConsumerState<AgentCanvasPanel> createState() => _AgentCanvasPanelState();
}

class _AgentCanvasPanelState extends ConsumerState<AgentCanvasPanel> {
  final AgentSurfaceRenderer _renderer =
      const PinnedGenUiAgentSurfaceRenderer();
  String? _selectedCanvasId;
  String? _requestedTerminalSessionId;
  bool _showHistory = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final requestedTerminalSessionId = ref.watch(
      agentCanvasSelectionProvider(widget.workspace.id),
    );
    ref.listen<String?>(agentCanvasSelectionProvider(widget.workspace.id), (
      _,
      next,
    ) {
      if (next == null || !mounted) {
        return;
      }
      setState(() {
        _requestedTerminalSessionId = next;
        _selectedCanvasId = null;
      });
    });
    final capabilities = ref.watch(agentCanvasCapabilitiesProvider);
    if (capabilities.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (capabilities.hasError ||
        capabilities.asData?.value['supported'] != true) {
      return const AleraEmptyState(
        title: 'Agent Canvas Unavailable',
        message: 'This runtime host does not support Agent Canvas. Restart Alera to use Agent Canvas.',
        icon: AleraIcons.agent,
      );
    }

    final canvases = ref.watch(agentCanvasesProvider(widget.workspace.id));
    return canvases.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AleraEmptyState(
        title: 'Agent Canvas Unavailable',
        message: 'Agent Canvas could not load: $error',
        icon: AleraIcons.error,
      ),
      data: (values) =>
          _buildContent(context, values, requestedTerminalSessionId),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<AgentCanvas> values,
    String? requestedTerminalSessionId,
  ) {
    final pinned = values.where((canvas) => canvas.pinned).toList();
    final active = values.where((canvas) => canvas.isActive && !canvas.pinned);
    final waiting = active
        .where((canvas) => canvas.state == AgentCanvasState.waiting)
        .toList();
    final live = active
        .where((canvas) => canvas.state == AgentCanvasState.live)
        .toList();
    final history = values
        .where((canvas) => canvas.state.isHistory && !canvas.pinned)
        .toList();
    final selected = _selectedCanvas(
      values,
      requestedTerminalSessionId ?? _requestedTerminalSessionId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PanelToolbar(
          showHistory: _showHistory,
          hasHistory: history.isNotEmpty,
          onShowHistoryChanged: (showHistory) {
            setState(() => _showHistory = showHistory);
          },
        ),
        if (values.isEmpty)
          const Expanded(
            child: AleraEmptyState(
              title: 'No Agent Canvases',
              message: 'Publish a run from an agent terminal to see its progress here.',
              icon: AleraIcons.agent,
            ),
          )
        else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: AleraTokens.agentCanvasListWidth,
                  child: _CanvasList(
                    pinned: pinned,
                    waiting: waiting,
                    live: live,
                    history: _showHistory ? history : const <AgentCanvas>[],
                    selectedCanvasId: selected?.id,
                    onSelect: (canvas) {
                      setState(() => _selectedCanvasId = canvas.id);
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selected == null
                      ? const AleraEmptyState(
                          message: 'Select an Agent Canvas to inspect its run.',
                        )
                      : _CanvasDetails(
                          canvas: selected,
                          busy: _busy,
                          renderer: _renderer,
                          onPinChanged: (pinned) =>
                              unawaited(_setPinned(selected, pinned)),
                          onComplete: selected.isActive
                              ? () => unawaited(_complete(selected))
                              : null,
                          onClose: selected.isActive
                              ? () => unawaited(_close(selected))
                              : null,
                          onRemove: selected.isActive
                              ? null
                              : () => unawaited(_remove(selected)),
                          onAction: (action) => _handleAction(selected, action),
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  AgentCanvas? _selectedCanvas(
    List<AgentCanvas> values,
    String? requestedTerminalSessionId,
  ) {
    final selectedId = _selectedCanvasId;
    if (selectedId != null) {
      for (final canvas in values) {
        if (canvas.id == selectedId) {
          return canvas;
        }
      }
    }
    if (requestedTerminalSessionId != null) {
      for (final canvas in values) {
        if (canvas.terminalSessionId == requestedTerminalSessionId) {
          return canvas;
        }
      }
    }
    final candidates = <AgentCanvas>[
      ...values.where((canvas) => canvas.pinned),
      ...values.where((canvas) => canvas.isActive && !canvas.pinned),
      ...values.where((canvas) => canvas.state.isHistory && !canvas.pinned),
    ];
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<void> _setPinned(AgentCanvas canvas, bool pinned) async {
    await _runBusy(() async {
      await ref.read(agentCanvasRepositoryProvider).pin(canvas.id, pinned);
    });
  }

  Future<void> _complete(AgentCanvas canvas) async {
    await _runBusy(() async {
      await ref.read(agentCanvasRepositoryProvider).complete(canvas.id);
    });
  }

  Future<void> _close(AgentCanvas canvas) async {
    final confirmed = await _confirm(
      title: 'Close Agent Canvas?',
      message: 'Closing freezes the current revision and stops live updates for this canvas.',
      confirmLabel: 'Close Canvas',
    );
    if (!confirmed) {
      return;
    }
    await _runBusy(() async {
      await ref.read(agentCanvasRepositoryProvider).close(canvas.id);
    });
  }

  Future<void> _remove(AgentCanvas canvas) async {
    final confirmed = await _confirm(
      title: 'Remove Agent Canvas?',
      message: 'This removes the retained canvas and its event history.',
      confirmLabel: 'Remove Canvas',
      destructive: true,
    );
    if (!confirmed) {
      return;
    }
    await _runBusy(() async {
      await ref.read(agentCanvasRepositoryProvider).remove(canvas.id);
      if (mounted && _selectedCanvasId == canvas.id) {
        setState(() => _selectedCanvasId = null);
      }
    });
  }

  Future<void> _handleAction(
    AgentCanvas canvas,
    Map<String, Object?> action,
  ) async {
    final kind = action['kind'];
    if (kind is! String || kind.isEmpty) {
      _showMessage('Agent Canvas action is missing its kind.', error: true);
      return;
    }
    final destructive = _destructiveActions.contains(kind);
    final controlled = _controlledActions.contains(kind);
    final requiresDialog =
        destructive || (controlled && kind != 'resolveDecision');
    if (requiresDialog) {
      final confirmed = await _confirm(
        title: destructive ? 'Confirm Destructive Action' : 'Confirm Action',
        message: destructive
            ? 'This action can change workspace or source control state.'
            : 'Confirm that you want to continue with this Agent Canvas action.',
        confirmLabel: 'Confirm',
        destructive: destructive,
      );
      if (!confirmed) {
        return;
      }
    }
    final request = <String, Object?>{
      ...action,
      if (controlled || destructive) 'confirmed': true,
      if (kind == 'focusTerminal' && action['terminalSessionId'] == null)
        'terminalSessionId': canvas.terminalSessionId,
    };
    try {
      await ref
          .read(agentCanvasRepositoryProvider)
          .action(canvasId: canvas.id, action: request);
      if (_destructiveActions.contains(kind) ||
          (_controlledActions.contains(kind) && kind != 'resolveDecision')) {
        final sourceControlAction = widget.onSourceControlAction;
        if (sourceControlAction == null) {
          _showMessage(
            'This Agent Canvas action is not connected to an Alera controller.',
            error: true,
          );
          return;
        }
        await sourceControlAction(kind, request);
        return;
      }
      await _performImmediateAction(canvas, request);
    } on Object catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _performImmediateAction(
    AgentCanvas canvas,
    Map<String, Object?> action,
  ) async {
    switch (action['kind']) {
      case 'openFile':
        final path = action['relativePath'];
        if (path is String) {
          await widget.onOpenFile(path);
        }
      case 'openDiff':
        final path = action['relativePath'];
        if (path is String) {
          await widget.onOpenDiff(path);
        }
      case 'openSearch':
        widget.onSwitchContextPanel(WorkbenchContextPanelTab.search);
      case 'focusTerminal':
        final sessionId = action['terminalSessionId'];
        widget.onFocusTerminal(
          sessionId is String && sessionId.isNotEmpty
              ? sessionId
              : canvas.terminalSessionId,
        );
      case 'openPullRequest':
        widget.onOpenPullRequest();
      case 'openArtifact':
        final artifactId = action['artifactId'];
        if (artifactId is String) {
          widget.onOpenArtifact(artifactId);
        }
      case 'copyText':
        final text = action['text'];
        if (text is String) {
          await Clipboard.setData(ClipboardData(text: text));
          _showMessage('Text copied to the clipboard.');
        }
      case 'switchContextPanel':
        final panel = _contextPanelFrom(action['panel']);
        if (panel != null) {
          widget.onSwitchContextPanel(panel);
        }
      default:
        _showMessage('Agent Canvas action completed.');
    }
  }

  Future<void> _runBusy(Future<void> Function() operation) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await operation();
    } on Object catch (error) {
      _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AleraConfirmDialog(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            destructive: destructive,
          ),
        ) ??
        false;
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: message,
      tone: error ? AleraToastTone.error : AleraToastTone.success,
    );
  }
}
