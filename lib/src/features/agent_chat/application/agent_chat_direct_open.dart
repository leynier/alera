import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_commands.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_direct_open.g.dart';

/// What New Agent Chat did.
enum AgentChatDirectOpenOutcome {
  /// A never-sent chat of the workspace was focused instead.
  reused,
  created,

  /// Another New Agent Chat for the workspace was still running.
  skipped,

  /// Nothing opened; a toast says why.
  failed,
}

/// How many never-sent candidates New Agent Chat reads before creating.
const int _reuseCandidateLimit = 3;

/// What the person is looking at: the active workspace and, in the opening
/// workspace, the focused side-panel key, the side panel's active tab, and
/// the workbench's active tab.
typedef _WorkbenchSelection = (String?, String?, String?, String?);

/// Reads providers for [AgentChatDirectOpener]; `WidgetRef` and
/// `ProviderContainer` both fit.
typedef AgentChatProviderReader = T Function<T>(ProviderListenable<T> provider);
typedef AgentChatProviderExists = bool Function(ProviderBase<Object?> provider);

/// New Agent Chat without a dialog: the chat starts with the resolved agent
/// and model and opens in the target pane with its composer focused. Only
/// one open per workspace runs at a time, and a failed create keeps its
/// request id so the next attempt cannot duplicate the chat on the runtime.
/// A cold create can take seconds; when the person selects something else
/// meanwhile, the chat's tab opens without being selected.
@Riverpod(keepAlive: true)
AgentChatDirectOpener agentChatDirectOpener(Ref ref) => AgentChatDirectOpener();

final class AgentChatDirectOpener {
  final Set<String> _opening = <String>{};
  final Map<String, String> _createRequestIds = <String, String>{};
  final Map<String, bool> _initialFocus = <String, bool>{};

  /// Whether a created chat's composer takes the keyboard when its surface
  /// mounts, whatever that surface's own autofocus: `null` when New Agent
  /// Chat did not ask, `true` when the person moved on to another field
  /// while it was created, so only a parked focus may be taken.
  bool? takeInitialFocus(String chatId) => _initialFocus.remove(chatId);

  Future<AgentChatDirectOpenOutcome> open({
    required AgentChatProviderReader read,
    required AgentChatProviderExists exists,
    required Workspace workspace,
    String? targetGroupId,
    String? launchingChatId,
    AgentChatComposerDraft? draft,
    VoidCallback? onOpenProviderSettings,
  }) async {
    if (!_opening.add(workspace.id)) return AgentChatDirectOpenOutcome.skipped;
    final startFocus = FocusManager.instance.primaryFocus;
    final startSelection = _selection(read, workspace.id);
    try {
      if (draft == null || draft.isEmpty) {
        if (await _reuse(read, exists, workspace) != null) {
          return AgentChatDirectOpenOutcome.reused;
        }
      }
      final selection = await _resolve(
        read,
        exists,
        workspace,
        launchingChatId,
        onOpenProviderSettings: onOpenProviderSettings,
      );
      if (selection == null) return AgentChatDirectOpenOutcome.failed;
      final requestId = _createRequestIds.putIfAbsent(
        workspace.id,
        read(agentChatIdGeneratorProvider),
      );
      final result = await read(agentChatRepositoryProvider).create(
        selection.$1?.createInput(
              requestId: requestId,
              workspaceId: workspace.id,
            ) ??
            AgentChatCreateInput(
              requestId: requestId,
              workspaceId: workspace.id,
            ),
      );
      _createRequestIds.remove(workspace.id);
      if (draft != null && !draft.isEmpty) {
        read(agentChatComposerDraftsProvider).write(
          result.chatId,
          draft,
          hostId: workspace.hostId,
          workspaceId: workspace.id,
        );
      }
      final activate = !_movedOn(
        startSelection,
        _selection(read, workspace.id),
        workspace.id,
        result.tabId,
      );
      if (activate) {
        final focus = FocusManager.instance.primaryFocus;
        _initialFocus[result.chatId] =
            focus != startFocus && !workbenchFocusIsParked();
      }
      await _openTab(read, workspace, result, targetGroupId, activate);
      if (activate) _focusIfStillAsked(read, result.chatId);
      return AgentChatDirectOpenOutcome.created;
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not start the chat: ${agentChatErrorMessage(error)}',
        tone: .error,
        actionLabel: agentChatTryAgainLabel,
        onAction: () => unawaited(
          open(
            read: read,
            exists: exists,
            workspace: workspace,
            targetGroupId: targetGroupId,
            launchingChatId: launchingChatId,
            draft: draft,
            onOpenProviderSettings: onOpenProviderSettings,
          ),
        ),
      );
      return AgentChatDirectOpenOutcome.failed;
    } finally {
      _opening.remove(workspace.id);
    }
  }

  _WorkbenchSelection _selection(
    AgentChatProviderReader read,
    String workspaceId,
  ) {
    final state = read(workbenchControllerProvider);
    final panel = state.workspacePanelFor(workspaceId);
    return (
      state.activeWorkspaceId,
      panel.focusedKey,
      panel.ensuredLayout(workspaceId).activeTabId,
      state.layoutFor(workspaceId)?.activeTabId,
    );
  }

  /// Whether the person left the workspace or selected another surface in
  /// it while the chat was created. A selection that moved to the new chat's
  /// own tab is the runtime's sync placing it, not the person.
  bool _movedOn(
    _WorkbenchSelection before,
    _WorkbenchSelection after,
    String workspaceId,
    String? tabId,
  ) {
    if (after.$1 != workspaceId || before.$1 != after.$1) return true;
    bool changed(String? was, String? now) =>
        was != now &&
        (tabId == null ||
            (now != tabId && now != WorkspacePanel.tabKey(tabId)));
    return changed(before.$2, after.$2) ||
        changed(before.$3, after.$3) ||
        changed(before.$4, after.$4);
  }

  /// A surface that mounted before the request was recorded, or that has
  /// not consumed it by the next frame, gets it through the composer
  /// command; a chat that is not on screen ignores it, and nothing is left
  /// behind for a later mount.
  void _focusIfStillAsked(AgentChatProviderReader read, String chatId) {
    // Read now: the widget behind [read] may be gone by the next frame.
    final commands = read(agentChatComposerCommandsProvider.notifier);
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      final guarded = _initialFocus.remove(chatId);
      if (guarded == null || (guarded && !workbenchFocusIsParked())) return;
      commands.focus(chatId);
    });
    binding.ensureVisualUpdate();
  }

  /// The chat exists on the runtime from here on, so a failure only reports:
  /// trying the create again would start a second chat.
  Future<void> _openTab(
    AgentChatProviderReader read,
    Workspace workspace,
    AgentChatOpenResult result,
    String? targetGroupId,
    bool activate,
  ) async {
    try {
      final tabId = result.tabId;
      if (tabId == null) {
        throw StateError('The runtime did not open a tab for the chat.');
      }
      await read(workbenchControllerProvider.notifier)
          .openPersistedWorkspaceTab(
            workspaceId: workspace.id,
            tabId: tabId,
            targetGroupId: targetGroupId,
            activate: activate,
            activateOnlyIfCurrent: true,
          );
    } on Object catch (error) {
      _initialFocus.remove(result.chatId);
      AleraToast.publish(
        message:
            'The chat started but its tab could not open: '
            '${agentChatErrorMessage(error)}',
        tone: .error,
      );
    }
  }

  /// Focuses a never-sent chat of [workspace] whose draft on this client is
  /// empty. Reuse only focuses; it never changes the chat, and it never
  /// switches workspaces.
  Future<String?> _reuse(
    AgentChatProviderReader read,
    AgentChatProviderExists exists,
    Workspace workspace,
  ) async {
    final drafts = read(agentChatComposerDraftsProvider);
    final candidates = <WorkspaceTabRecord>[
      for (final tab in read(workbenchControllerProvider).tabsFor(workspace.id))
        if (tab.kind == WorkspaceTabKind.agentChat && tab.agentChatId != null)
          tab,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final unread = <WorkspaceTabRecord>[];
    for (final tab in candidates.take(_reuseCandidateLimit)) {
      final draft = await drafts.hydrate(
        tab.agentChatId!,
        hostId: workspace.hostId,
        workspaceId: workspace.id,
      );
      if (!draft.isEmpty) continue;
      final controller = agentChatControllerProvider(
        tab.agentChatId!,
        workspace.id,
      );
      if (!exists(controller)) {
        unread.add(tab);
        continue;
      }
      final state = read(controller);
      if (state.thread != null && state.neverSent && !state.archived) {
        return _focus(read, workspace, tab);
      }
    }
    final repository = read(agentChatRepositoryProvider);
    final reads = await Future.wait(<Future<bool>>[
      for (final tab in unread.take(_reuseCandidateLimit))
        repository
            .snapshot(
              AgentChatRef(chatId: tab.agentChatId!, workspaceId: workspace.id),
            )
            .then(
              (snapshot) => snapshot.neverSent && !snapshot.archived,
              onError: (Object _) => false,
            ),
    ]);
    for (final (index, neverSent) in reads.indexed) {
      if (neverSent) return _focus(read, workspace, unread[index]);
    }
    return null;
  }

  Future<String> _focus(
    AgentChatProviderReader read,
    Workspace workspace,
    WorkspaceTabRecord tab,
  ) async {
    final workbench = read(workbenchControllerProvider.notifier);
    if (read(workbenchControllerProvider).activeWorkspaceId == workspace.id) {
      await workbench.selectWorkspaceTab(
        workspaceId: workspace.id,
        tabId: tab.id,
      );
      read(agentChatComposerCommandsProvider.notifier).focus(tab.agentChatId!);
    }
    return tab.id;
  }

  /// The agent and model a new chat starts with, as a one-field record so a
  /// runtime that keeps unselected drafts can be told "none". `null` means
  /// nothing can be created and the person has been told why.
  Future<(AgentChatSelection?,)?> _resolve(
    AgentChatProviderReader read,
    AgentChatProviderExists exists,
    Workspace workspace,
    String? launchingChatId, {
    VoidCallback? onOpenProviderSettings,
  }) async {
    // The repositories are read directly: a `read` of an auto-disposed
    // provider's future may not outlive a slow runtime round trip.
    final List<AgentChatProviderInstance> catalog;
    try {
      catalog = await read(agentChatRepositoryProvider)
          .providers(workspaceId: workspace.id);
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not load agents: ${agentChatErrorMessage(error)}',
        tone: .error,
        actionLabel: onOpenProviderSettings == null
            ? null
            : agentChatOpenProviderSettingsLabel,
        onAction: onOpenProviderSettings,
      );
      return null;
    }
    final preferences = await _preferences(read, workspace);
    final launching = _launchingSelection(
      read,
      exists,
      workspace,
      launchingChatId,
    );
    final remembered =
        preferences.rememberedSelection ??
        read(agentChatLaunchPreferenceProvider);
    final chain = <AgentChatSelection?>[
      preferences.projectDefaults[workspace.projectId],
      launching,
      preferences.defaultSelection,
      remembered,
    ];
    final resolved = resolveAgentChatSelection(
      providers: catalog,
      projectDefault: chain[0],
      launchingSelection: chain[1],
      defaultSelection: chain[2],
      rememberedSelection: chain[3],
    );
    if (resolved != null) return (resolved,);
    // A known agent that cannot start yet still gets its chat: the chip
    // shows why and offers the provider settings.
    final enabled = <String>{
      for (final instance in catalog)
        if (instance.enabled) instance.id,
    };
    final known =
        chain.nonNulls
            .where(
              (selection) => enabled.contains(selection.providerInstanceId),
            )
            .firstOrNull ??
        catalog
            .where((instance) => instance.enabled)
            .map(
              (instance) => AgentChatSelection(providerInstanceId: instance.id),
            )
            .firstOrNull;
    if (known != null) return (known,);
    if (await read(agentChatLifecycleRepositoryProvider)
        .supports(AgentChatWire.unselectedDraftCapability)
        .catchError((Object _) => false)) {
      return (null,);
    }
    AleraToast.publish(
      message: 'No agent is available on this runtime.',
      tone: .warning,
      actionLabel: onOpenProviderSettings == null
          ? null
          : agentChatOpenProviderSettingsLabel,
      onAction: onOpenProviderSettings,
    );
    return null;
  }

  /// Empty preferences when the runtime keeps none or cannot be read: a
  /// default that cannot be read must not stop a new chat.
  Future<AgentChatPreferences> _preferences(
    AgentChatProviderReader read,
    Workspace workspace,
  ) async {
    final settings = read(agentChatSettingsRepositoryProvider);
    try {
      if (!await settings.preferencesSupported()) {
        return const AgentChatPreferences();
      }
      return await settings.preferences(
        hostId: agentChatHostKey(workspace.hostId),
      );
    } on Object {
      return const AgentChatPreferences();
    }
  }

  AgentChatSelection? _launchingSelection(
    AgentChatProviderReader read,
    AgentChatProviderExists exists,
    Workspace workspace,
    String? chatId,
  ) {
    if (chatId == null) return null;
    final controller = agentChatControllerProvider(chatId, workspace.id);
    if (!exists(controller)) return null;
    final thread = read(controller).thread;
    if (thread == null || thread.providerInstanceId.isEmpty) return null;
    return AgentChatSelection(
      providerInstanceId: thread.providerInstanceId,
      model: thread.session.model,
      runtimeMode: thread.session.runtimeMode,
      interactionMode: thread.session.interactionMode,
    );
  }
}

/// New Agent Chat for [workspace] from a widget. [launchingChatId] is the
/// chat the command came from, whose agent and model the new chat inherits
/// when no project default applies. It reads through [container] rather
/// than a widget's ref, because a cold create can outlast the widget that
/// asked for it.
Future<AgentChatDirectOpenOutcome> openNewAgentChat(
  ProviderContainer container, {
  required Workspace workspace,
  String? targetGroupId,
  String? launchingChatId,
  AgentChatComposerDraft? draft,
  VoidCallback? onOpenProviderSettings,
}) => container
    .read(agentChatDirectOpenerProvider)
    .open(
      read: container.read,
      exists: container.exists,
      workspace: workspace,
      targetGroupId: targetGroupId,
      launchingChatId: launchingChatId,
      draft: draft,
      onOpenProviderSettings: onOpenProviderSettings,
    );
