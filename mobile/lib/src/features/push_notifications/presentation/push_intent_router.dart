import 'dart:async';

import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/automations/presentation/automations_screen.dart';
import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/runtime_workspaces_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> routePushIntent(WidgetRef ref, PushNavigationIntent intent) async {
  final navigator = aleraNavigatorKey.currentState;
  if (navigator == null) {
    return;
  }
  navigator.popUntil((route) => route.isFirst);
  if (intent.accountId != null) {
    final accounts = await ref.read(cloudAccountsControllerProvider.future);
    if (!accounts.any((item) => item.account.id == intent.accountId)) {
      _showMessage('This account is not on this phone');
      return;
    }
  }
  final hosts = await ref.read(pairedHostsControllerProvider.future);
  final host = hosts
      .where((item) => item.runtimeId == intent.runtimeId)
      .firstOrNull;
  if (host == null) {
    _showMessage('This host is not paired');
    return;
  }
  if (intent.eventKind == PushEventKind.automation) {
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => AutomationsScreen(host: host)),
      ),
    );
    return;
  }
  unawaited(
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RuntimeWorkspacesScreen(host: host),
      ),
    ),
  );
  if (intent.workspaceId == null ||
      intent.eventKind == PushEventKind.terminalExit) {
    return;
  }
  try {
    final client = await ref.read(
      hostConnectionControllerProvider(host.id).future,
    );
    final workspaces = await client.listWorkspaces();
    final workspace = workspaces
        .where((item) => item.id == intent.workspaceId)
        .firstOrNull;
    if (workspace == null) {
      _showMessage('The workspace is no longer available');
      return;
    }
    var terminalExists = false;
    if (intent.shouldOpenTerminal) {
      final tabs = await client.listTabs(workspace.id);
      terminalExists = tabs.any(
        (tab) => tab.id == intent.tabId && tab.isTerminal,
      );
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceTabsScreen(
            hostId: host.id,
            workspace: workspace,
            initialTabId: terminalExists ? intent.tabId : null,
            selectFallbackTab: !intent.shouldOpenTerminal || terminalExists,
          ),
        ),
      ),
    );
    if (intent.shouldOpenTerminal && !terminalExists) {
      _showMessage('The terminal is no longer available');
    }
  } on Object {
    _showMessage('Open the host to refresh this notification');
  }
}

void _showMessage(String message) {
  final context = aleraNavigatorKey.currentContext;
  if (context == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
