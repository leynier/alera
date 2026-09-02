import 'dart:async';

import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/settings/application/settings_providers.dart';
import 'package:alera/src/features/settings/application/runtime_settings_changes.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  bool _loadStarted = false;

  SettingsRepository get _repository => ref.read(settingsRepositoryProvider);

  @override
  AleraSettings build() {
    ref.listen(runtimeSettingsChangesProvider, (previous, next) {
      if (next.hasValue) {
        unawaited(load());
      }
    });
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(load());
    }
    return AleraSettings.defaults;
  }

  /// Loads persisted settings, keeping the defaults if that fails.
  ///
  /// Callers start this without awaiting it, so a throw here used to escape as
  /// an uncaught zone error that nothing recorded. Settings failing to load is
  /// worth a log line, not a crash: the defaults are a usable state.
  Future<void> load() => _serialize(() async {
    try {
      state = await _repository.load();
    } on Object catch (error, stackTrace) {
      Logger('SettingsController').warning(
        'failed to load settings; keeping the current values',
        error,
        stackTrace,
      );
    }
  });

  Future<void> updateTerminal(
    TerminalSettings Function(TerminalSettings) edit,
  ) => _serialize(() async {
    await _save(state.copyWith(terminal: edit(state.terminal)));
  });

  Future<void> updateEditor(EditorSettings Function(EditorSettings) edit) =>
      _serialize(() async {
        await _save(state.copyWith(editor: edit(state.editor)));
      });

  Future<void> updateAiAssist(
    AiAssistSettings Function(AiAssistSettings) edit,
  ) => _serialize(() async {
    await _save(state.copyWith(aiAssist: edit(state.aiAssist)));
  });

  Future<void> updateAiDictation(
    AiDictationSettings Function(AiDictationSettings) edit,
  ) => _serialize(() async {
    await _save(state.copyWith(aiDictation: edit(state.aiDictation)));
  });

  Future<void> resetAiDictation() => _serialize(() async {
    await _save(state.copyWith(aiDictation: .defaults));
  });

  Future<void> updateTextActions(
    TextActionsSettings Function(TextActionsSettings) edit,
  ) => _serialize(() async {
    await _save(state.copyWith(textActions: edit(state.textActions)));
  });

  Future<void> updateCodexChat(CodexChatSettings settings) =>
      _serialize(() async {
        await _save(state.copyWith(codexChat: settings));
      });

  Future<void> resetTextActions() => _serialize(() async {
    await _save(state.copyWith(textActions: .defaults));
  });

  Future<void> resetAiAssistSettings() => _serialize(() async {
    await _save(state.copyWith(aiAssist: .defaults));
  });

  Future<void> resetEditorSettings() => _serialize(() async {
    await _save(state.copyWith(editor: .defaults));
  });

  Future<void> resetTerminalSettings() => _serialize(() async {
    await _save(state.copyWith(terminal: .defaults));
  });

  Future<void> updateWorkspaceDirectory(String? path) => _serialize(() async {
    await _save(
      state.copyWith(general: state.general.copyWith(workspaceDirectory: path)),
    );
  });

  Future<void> setConfirmProjectRemoval(bool value) => _serialize(() async {
    if (state.general.confirmProjectRemoval == value) {
      return;
    }
    await _save(
      state.copyWith(
        general: state.general.copyWith(confirmProjectRemoval: value),
      ),
    );
  });

  Future<void> setDiagnosticsLogLevel(DiagnosticsLogLevel value) =>
      _serialize(() async {
        if (state.diagnostics.logLevel == value) {
          return;
        }
        await _save(
          state.copyWith(
            diagnostics: state.diagnostics.copyWith(logLevel: value),
          ),
        );
      });

  Future<void> setCrashReportingEnabled(bool value) => _serialize(() async {
    if (state.diagnostics.crashReportingEnabled == value) {
      return;
    }
    await _save(
      state.copyWith(
        diagnostics: state.diagnostics.copyWith(crashReportingEnabled: value),
      ),
    );
  });

  Future<void> setConfirmWorkspaceRemoval(bool value) => _serialize(() async {
    if (state.general.confirmWorkspaceRemoval == value) {
      return;
    }
    await _save(
      state.copyWith(
        general: state.general.copyWith(confirmWorkspaceRemoval: value),
      ),
    );
  });

  Future<void> setKeepAliveEnabled(bool value) => _serialize(() async {
    if (state.general.keepAliveEnabled == value) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(keepAliveEnabled: value)),
    );
  });

  Future<void> setShowTrayIcon(bool value) => _serialize(() async {
    if (state.general.showTrayIcon == value) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(showTrayIcon: value)),
    );
  });

  Future<void> setShowDockBadge(bool value) => _serialize(() async {
    if (state.general.showDockBadge == value) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(showDockBadge: value)),
    );
  });

  Future<void> setShowTrayBadge(bool value) => _serialize(() async {
    if (state.general.showTrayBadge == value) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(showTrayBadge: value)),
    );
  });

  Future<void> setShowPullRequestStatusInSidebar(bool value) =>
      _serialize(() async {
        if (state.general.showPullRequestStatusInSidebar == value) {
          return;
        }
        await _save(
          state.copyWith(
            general: state.general.copyWith(
              showPullRequestStatusInSidebar: value,
            ),
          ),
        );
      });

  Future<void> setPullRequestFailureNotificationsEnabled(bool value) =>
      _serialize(() async {
        if (state.general.pullRequestFailureNotificationsEnabled == value) {
          return;
        }
        await _save(
          state.copyWith(
            general: state.general.copyWith(
              pullRequestFailureNotificationsEnabled: value,
            ),
          ),
        );
      });

  Future<void> setAgentStatusHookEnabled(AgentType agentType, bool value) =>
      _serialize(() async {
        final current = state.agents.agentStatusHooks;
        final next = switch (agentType) {
          AgentType.codex => current.copyWith(codex: value),
          AgentType.claude => current.copyWith(claude: value),
          AgentType.copilot => current.copyWith(copilot: value),
          AgentType.cursor => current.copyWith(cursor: value),
          AgentType.agy => current.copyWith(agy: value),
          AgentType.opencode => current.copyWith(opencode: value),
          AgentType.opencode2 => current.copyWith(opencode2: value),
          AgentType.pi => current.copyWith(pi: value),
          AgentType.amp => current.copyWith(amp: value),
          AgentType.grok => current.copyWith(grok: value),
          AgentType.fx => current.copyWith(fx: value),
        };
        if (current == next) {
          return;
        }
        await _save(
          state.copyWith(agents: state.agents.copyWith(agentStatusHooks: next)),
        );
      });

  Future<void> setAgentStatusNotificationsEnabled(bool value) => _serialize(
    () async {
      if (state.agents.agentStatusNotificationsEnabled == value) {
        return;
      }
      await _save(
        state.copyWith(
          agents: state.agents.copyWith(agentStatusNotificationsEnabled: value),
        ),
      );
    },
  );

  Future<void> setAgentStatusFinishedNotificationsEnabled(bool value) =>
      _serialize(() async {
        if (state.agents.agentStatusFinishedNotificationsEnabled == value) {
          return;
        }
        await _save(
          state.copyWith(
            agents: state.agents.copyWith(
              agentStatusFinishedNotificationsEnabled: value,
            ),
          ),
        );
      });

  Future<void> setKeepComputerAwakeWhileAgentsWork(bool value) =>
      _serialize(() async {
        if (state.agents.keepComputerAwakeWhileAgentsWork == value) {
          return;
        }
        await _save(
          state.copyWith(
            agents: state.agents.copyWith(
              keepComputerAwakeWhileAgentsWork: value,
            ),
          ),
        );
      });

  Future<void> setShowTabTitlesInSidebar(bool value) => _serialize(() async {
    if (state.agents.showTabTitlesInSidebar == value) {
      return;
    }
    await _save(
      state.copyWith(
        agents: state.agents.copyWith(showTabTitlesInSidebar: value),
      ),
    );
  });

  Future<void> setDefaultAgentProfile(String? profileId) => _serialize(
    () async {
      final normalized = profileId?.trim();
      final next = normalized == null || normalized.isEmpty ? null : normalized;
      if (state.agents.defaultAgentProfileId == next) {
        return;
      }
      await _save(
        state.copyWith(
          agents: state.agents.copyWith(defaultAgentProfileId: next),
        ),
      );
    },
  );

  Future<void> setAgentQuotaProviderEnabled({
    required String hostId,
    required AgentQuotaProviderId provider,
    required bool value,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    final enabled = <AgentQuotaProviderId>{...current.enabledProviders};
    if (value) {
      enabled.add(provider);
    } else {
      enabled.remove(provider);
    }
    await _saveQuotaHost(
      hostId,
      current.copyWith(enabledProviders: enabled.toList()),
    );
  });

  Future<void> setAgentQuotaProviderOrder({
    required String hostId,
    required List<AgentQuotaProviderId> providers,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    final enabled = current.enabledProviders.toSet();
    final ordered = <AgentQuotaProviderId>[
      for (final provider in providers)
        if (enabled.remove(provider)) provider,
      for (final provider in current.enabledProviders)
        if (enabled.remove(provider)) provider,
    ];
    await _saveQuotaHost(hostId, current.copyWith(enabledProviders: ordered));
  });

  Future<void> setClaudeQuotaProfiles({
    required String hostId,
    required List<ClaudeQuotaProfileSettings> profiles,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    final selected =
        current.selectedClaudeProfile == 'default' ||
            profiles.any(
              (profile) => profile.profile == current.selectedClaudeProfile,
            )
        ? current.selectedClaudeProfile
        : 'default';
    final validClaudeKeys = <String>{
      AgentQuotaHostSettings.quotaPinKey(.claude),
      for (final profile in profiles)
        AgentQuotaHostSettings.quotaPinKey(
          .claude,
          claudeAccountId: profile.profile,
        ),
    };
    final unpinned = current.unpinnedQuotaKeys
        .where(
          (key) => !key.startsWith('claude:') || validClaudeKeys.contains(key),
        )
        .toList();
    await _saveQuotaHost(
      hostId,
      current.copyWith(
        claudeProfiles: profiles,
        selectedClaudeProfile: selected,
        unpinnedQuotaKeys: unpinned,
      ),
    );
  });

  Future<void> setAgentQuotaPinned({
    required String hostId,
    required String pinKey,
    required bool pinned,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    final unpinned = <String>{...current.unpinnedQuotaKeys};
    if (pinned) {
      unpinned.remove(pinKey);
    } else {
      unpinned.add(pinKey);
    }
    await _saveQuotaHost(
      hostId,
      current.copyWith(unpinnedQuotaKeys: unpinned.toList()),
    );
  });

  Future<void> setClaudeDefaultQuotaEnabled({
    required String hostId,
    required bool value,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    await _saveQuotaHost(hostId, current.copyWith(claudeDefaultEnabled: value));
  });

  Future<void> setClaudeDefaultShowInUsage({
    required String hostId,
    required bool value,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    await _saveQuotaHost(
      hostId,
      current.copyWith(claudeDefaultShowInUsage: value),
    );
  });

  Future<void> setSelectedClaudeQuotaProfile({
    required String hostId,
    required String profile,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    await _saveQuotaHost(
      hostId,
      current.copyWith(selectedClaudeProfile: profile),
    );
  });

  Future<void> setAgentQuotaEnvironment({
    required String hostId,
    required AgentQuotaEnvironmentSettings environment,
  }) => _serialize(() async {
    final current = state.agents.quotas.forHost(hostId);
    await _saveQuotaHost(hostId, current.copyWith(environment: environment));
  });

  Future<void> _saveQuotaHost(
    String hostId,
    AgentQuotaHostSettings hostSettings,
  ) async {
    final quotas = state.agents.quotas.withHost(hostId, hostSettings);
    await _save(state.copyWith(agents: state.agents.copyWith(quotas: quotas)));
  }

  /// Sets the bindings for [id]. A null [chords] restores the default; an empty
  /// list disables the action.
  Future<void> setActionBindings(KeyboardActionId id, List<String>? chords) =>
      _serialize(() async {
        await _save(
          state.copyWith(keyboard: state.keyboard.copyWithOverride(id, chords)),
        );
      });

  /// Applies several binding changes atomically (used for conflict reassignment,
  /// where one action gains a chord and another loses it). A null value
  /// restores the default for that action.
  Future<void> applyBindingChanges(
    Map<KeyboardActionId, List<String>?> changes,
  ) => _serialize(() async {
    var keyboard = state.keyboard;
    for (final entry in changes.entries) {
      keyboard = keyboard.copyWithOverride(entry.key, entry.value);
    }
    await _save(state.copyWith(keyboard: keyboard));
  });

  Future<void> setTerminalShortcutPolicy(TerminalShortcutPolicy policy) =>
      _serialize(() async {
        if (state.keyboard.terminalPolicy == policy) {
          return;
        }
        await _save(
          state.copyWith(keyboard: state.keyboard.copyWithPolicy(policy)),
        );
      });

  Future<void> resetKeyboardShortcuts() => _serialize(() async {
    await _save(state.copyWith(keyboard: state.keyboard.cleared()));
  });

  Future<void> markStarClicked() => _serialize(() async {
    if (state.general.starClicked) {
      return;
    }
    await _save(
      state.copyWith(general: state.general.copyWith(starClicked: true)),
    );
  });

  Future<void>? _operations;

  // Construct each mutation after prior persistence, including reloads from runtime events.
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operations == null
        ? operation()
        : _operations!.then((_) => operation());
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _operations = tail;
    unawaited(
      tail.then((_) {
        if (identical(_operations, tail)) _operations = null;
      }),
    );
    return next;
  }

  Future<void> _save(AleraSettings settings) async {
    await _repository.save(settings);
    state = settings;
  }
}
