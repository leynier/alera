import 'dart:async';

import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/material.dart';

/// Refreshes visible terminals on workspace entry and terminal selection.
class const WorkspaceTerminalRefresh({
  super.key,
  required final String? workspaceId,
  required final bool ready,
  required final List<String> terminalTabIds,
  final String? selectedTabId,
  required final TerminalRuntime terminalRuntime,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<WorkspaceTerminalRefresh> createState() =>
      _WorkspaceTerminalRefreshState();
}

class _WorkspaceTerminalRefreshState extends State<WorkspaceTerminalRefresh> {
  final _startingSessions = <TerminalSessionHandle, VoidCallback>{};
  final _pendingSessions = <TerminalSessionHandle>{};
  int _generation = 0;
  bool _entryPending = true;
  bool _selectionPending = false;
  bool _captureScheduled = false;

  @override
  void didUpdateWidget(WorkspaceTerminalRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workspaceId != oldWidget.workspaceId ||
        widget.terminalRuntime != oldWidget.terminalRuntime) {
      _generation++;
      _entryPending = true;
      _selectionPending = false;
      _captureScheduled = false;
      _clearStartingSessions();
    } else if (widget.selectedTabId != oldWidget.selectedTabId) {
      _selectionPending = true;
    }
  }

  @override
  void dispose() {
    _clearStartingSessions();
    super.dispose();
  }

  void _clearStartingSessions() {
    for (final entry in _startingSessions.entries) {
      entry.key.removeListener(entry.value);
    }
    _startingSessions.clear();
    _pendingSessions.clear();
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _generation && widget.ready;

  @override
  Widget build(BuildContext context) {
    if ((_entryPending || _selectionPending) &&
        !_captureScheduled &&
        widget.workspaceId != null &&
        widget.ready) {
      _captureScheduled = true;
      final generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // TerminalSurface starts sessions in its own post-frame callback.
        final nextFrame = WidgetsBinding.instance.endOfFrame;
        WidgetsBinding.instance.scheduleFrame();
        await nextFrame;
        if (!mounted || generation != _generation) return;
        _captureScheduled = false;
        if (!widget.ready) return;
        final tabIds = _entryPending
            ? widget.terminalTabIds.toSet()
            : <String>{
                if (widget.selectedTabId case final tabId?
                    when widget.terminalTabIds.contains(tabId))
                  tabId,
              };
        _entryPending = false;
        _selectionPending = false;
        // Leases reflect the panes actually rendered, including both panels
        // and splits, without creating handles for background tabs.
        for (final tabId in tabIds) {
          final session = widget.terminalRuntime.peekSession(tabId);
          if (session == null ||
              session.workspaceId != widget.workspaceId ||
              !session.isVisible) {
            continue;
          }
          _refreshWhenStarted(session, generation);
        }
      });
    }
    return widget.child;
  }

  void _refreshWhenStarted(TerminalSessionHandle session, int generation) {
    if (!_pendingSessions.add(session)) return;
    if (!session.isStarting) {
      unawaited(_refresh(session, generation));
      return;
    }
    void onStarted() {
      if (session.isStarting) return;
      session.removeListener(onStarted);
      _startingSessions.remove(session);
      // Startup may replace the loading surface with the terminal view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_refresh(session, generation));
      });
    }

    _startingSessions[session] = onStarted;
    session.addListener(onStarted);
  }

  Future<void> _refresh(TerminalSessionHandle session, int generation) async {
    try {
      if (!_isCurrent(generation) ||
          !session.isVisible ||
          !identical(
            widget.terminalRuntime.peekSession(session.tabId),
            session,
          )) {
        return;
      }
      await session.refreshRendering();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Alera workbench',
          context: ErrorDescription('while refreshing a visible terminal'),
        ),
      );
    } finally {
      if (generation == _generation) _pendingSessions.remove(session);
    }
  }
}
