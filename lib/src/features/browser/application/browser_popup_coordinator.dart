// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_popup.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/foundation.dart';

typedef BrowserWorkspaceTabCreator = Future<WorkspaceTabRecord> Function({
  required String pageId,
  required String workspaceId,
  required String profileId,
  required String initialUrl,
});

final class BrowserPopupCoordinator({
  required this._registry,
  required this._createWorkspaceTab,
  DateTime Function()? now,
}) {
  this : _now = now ?? _defaultNow {
    _registrySubscription = _registry.events.listen(_onRegistryEvent);
  }

  final BrowserSessionRegistry _registry;
  final BrowserWorkspaceTabCreator _createWorkspaceTab;
  final DateTime Function() _now;
  final Set<String> _transientPageIds = <String>{};
  late final StreamSubscription<BrowserRegistryEvent> _registrySubscription;
  var _disposed = false;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @visibleForTesting
  int get debugTransientPageCount => _transientPageIds.length;

  Future<BrowserPopupDecision> decide(BrowserPopupRequest request) async {
    final opener = _registry.handleForPageId(request.openerPageId);
    final targetUrl = request.url ?? Uri.parse('about:blank');
    if (opener == null || !_allowedPopupUrl(targetUrl)) {
      return const BrowserPopupDecision.deny();
    }
    if (request.requiresOpener) {
      if (!request.trusted) {
        return const BrowserPopupDecision.deny();
      }
      final state = opener.state;
      _transientPageIds.add(request.transientPageId);
      try {
        final handle = await _registry.adoptTransientSession(
          page: BrowserPage(
            pageId: request.transientPageId,
            workspaceId: state.workspaceId,
            profileId: state.profileId,
            initialUrl: targetUrl,
            createdAt: _now(),
          ),
          openerPageId: request.openerPageId,
        );
        if (handle.state.engineAvailability !=
            BrowserEngineAvailability.available) {
          _transientPageIds.remove(request.transientPageId);
          await handle.close();
          return const BrowserPopupDecision.deny();
        }
        return BrowserPopupDecision.openInPage(request.transientPageId);
      } on Object {
        _transientPageIds.remove(request.transientPageId);
        rethrow;
      }
    }
    if (!request.userInitiated || !request.trusted) {
      return const BrowserPopupDecision.deny();
    }
    final openerState = opener.state;
    final adopted = await _registry.adoptTransientSession(
      page: BrowserPage(
        pageId: request.transientPageId,
        workspaceId: openerState.workspaceId,
        profileId: openerState.profileId,
        initialUrl: targetUrl,
        createdAt: _now(),
      ),
    );
    if (adopted.state.engineAvailability !=
        BrowserEngineAvailability.available) {
      await adopted.close();
      return const BrowserPopupDecision.deny();
    }
    try {
      final tab = await _createWorkspaceTab(
        pageId: request.transientPageId,
        workspaceId: openerState.workspaceId,
        profileId: openerState.profileId,
        initialUrl: targetUrl.toString(),
      );
      await _registry.sessionFor(tab);
      await _registry.promoteTransientPage(request.transientPageId);
      return BrowserPopupDecision.openInPage(request.transientPageId);
    } on Object {
      await adopted.close();
      rethrow;
    }
  }

  Future<void> closeTransientPage(String pageId) async {
    _transientPageIds.remove(pageId);
    await _registry.closePage(pageId);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _registrySubscription.cancel();
    for (final pageId in _transientPageIds.toList(growable: false)) {
      await closeTransientPage(pageId);
    }
  }

  void _onRegistryEvent(BrowserRegistryEvent event) {
    if (event.kind == BrowserRegistryEventKind.closed) {
      _transientPageIds.remove(event.pageId);
    }
  }
}

bool _allowedPopupUrl(Uri url) {
  if (url.toString() == 'about:blank') {
    return true;
  }
  return (url.scheme == 'http' || url.scheme == 'https') &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;
}
