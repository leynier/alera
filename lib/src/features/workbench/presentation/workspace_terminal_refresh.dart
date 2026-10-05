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
  final _waitingSessions =
      <
        TerminalSessionHandle,
        ({VoidCallback changed, VoidCallback disposed})
      >{};
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
      _clearWaitingSessions();
    } else if (widget.selectedTabId != oldWidget.selectedTabId) {
      _selectionPending = true;
    }
  }

  @override
  void dispose() {
    _clearWaitingSessions();
    super.dispose();
  }

  void _stopWaiting(TerminalSessionHandle session) {
    final callbacks = _waitingSessions.remove(session);
    if (callbacks == null) return;
    session.removeListener(callbacks.changed);
    session.restoreProgress.removeListener(callbacks.changed);
    session.disposal.removeListener(callbacks.disposed);
  }

  void _clearWaitingSessions() {
    for (final session in _waitingSessions.keys.toList()) {
      _stopWaiting(session);
    }
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
          _refreshWhenReady(session, generation);
        }
      });
    }
    return widget.child;
  }

  bool _sessionIsReady(TerminalSessionHandle session) =>
      !session.isStarting &&
      !session.isResumingOutput &&
      session.restoreProgress.value == null;

  void _refreshWhenReady(TerminalSessionHandle session, int generation) {
    if (!_pendingSessions.add(session)) return;
    var scheduled = false;
    void onChanged() {
      if (scheduled || !_sessionIsReady(session)) return;
      scheduled = true;
      // Restore or resume can begin after startup. Recheck after layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduled = false;
        if (!_waitingSessions.containsKey(session) || !_isCurrent(generation)) {
          return;
        }
        if (!_sessionIsReady(session)) return;
        _stopWaiting(session);
        unawaited(_refresh(session, generation));
      });
      WidgetsBinding.instance.scheduleFrame();
    }

    void onDisposed() {
      _stopWaiting(session);
      _pendingSessions.remove(session);
    }

    _waitingSessions[session] = (changed: onChanged, disposed: onDisposed);
    session.addListener(onChanged);
    session.restoreProgress.addListener(onChanged);
    session.disposal.addListener(onDisposed);
    onChanged();
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
