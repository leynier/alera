import 'dart:async';

import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/runs/application/activity_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
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
  if (activitySectionForPush(intent) case final section?) {
    ref
        .read(mobileActivitySectionControllerProvider(host.id).notifier)
        .select(section);
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ActivityScreen(
            hostId: host.id,
            initialSection: section,
            initialRunId: section == ActivitySection.runs ? intent.runId : null,
            initialGateId: intent.gateId,
            initialThreadId: intent.threadId,
            initialAutomationId: section == ActivitySection.automations
                ? intent.automationId
                : null,
            initialAutomationRunId: section == ActivitySection.automations
                ? intent.runId
                : null,
            initialChatTaskId: section == ActivitySection.chatTasks
                ? intent.taskId
                : null,
          ),
        ),
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
    WorkspaceTabSummary? targetTab;
    final expectsTab =
        intent.shouldOpenTerminal ||
        intent.eventKind == PushEventKind.agentChat;
    if (intent.shouldOpenTerminal || intent.shouldOpenAgentChat) {
      final tabs = await client.listTabs(workspace.id);
      targetTab = tabForPushIntent(intent, tabs);
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkspaceTabsScreen(
            hostId: host.id,
            workspace: workspace,
            initialTabId: targetTab?.id,
            selectFallbackTab: !expectsTab || targetTab != null,
          ),
        ),
      ),
    );
    if (expectsTab && targetTab == null) {
      _showMessage(
        intent.eventKind == PushEventKind.agentChat
            ? 'The agent chat is no longer available'
            : 'The terminal is no longer available',
      );
    }
  } on Object {
    _showMessage('Open the host to refresh this notification');
  }
}

/// Where in Activity a notification opens, or null when it belongs to a
/// workspace or terminal instead.
ActivitySection? activitySectionForPush(PushNavigationIntent intent) =>
    switch (intent.eventKind) {
      PushEventKind.runGate when intent.opensRun => ActivitySection.runs,
      PushEventKind.inboxReply => ActivitySection.questions,
      PushEventKind.automation => ActivitySection.automations,
      PushEventKind.chatTask => ActivitySection.chatTasks,
      _ => null,
    };

/// Match the chat identity as well as its tab kind so a stale notification
/// cannot activate a terminal or another chat that inherited the tab ID.
WorkspaceTabSummary? tabForPushIntent(
  PushNavigationIntent intent,
  Iterable<WorkspaceTabSummary> tabs,
) {
  final eligible = tabs.where((tab) => tab.workspaceId == intent.workspaceId);
  if (intent.shouldOpenAgentChat) {
    return eligible
        .where((tab) => tab.isAgentChat && tab.agentChatId == intent.chatId)
        .firstOrNull;
  }
  if (intent.shouldOpenTerminal) {
    return eligible
        .where((tab) => tab.isTerminal && tab.id == intent.tabId)
        .firstOrNull;
  }
  return null;
}

void _showMessage(String message) {
  final context = aleraNavigatorKey.currentContext;
  if (context == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
