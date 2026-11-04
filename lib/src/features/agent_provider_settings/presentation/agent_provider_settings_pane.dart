import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_choice_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_failure.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_hosts.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_providers.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_entries.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_model_rows.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_defaults_group.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_detail.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_dialogs.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_host_bar.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_launch_groups.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_list_row.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_models_group.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'agent_provider_settings_pane_actions.dart';
part 'agent_provider_settings_pane_groups.dart';

/// Settings > Providers: the Agent Chat provider instances of one host, with
/// their verified status, launch definition, write-only secrets, models and
/// defaults. [initialHostId] (null for This Device) and
/// [initialProviderInstanceId] open the pane on that host and row.
class const AgentProviderSettingsPane({
  super.key,
  final String? initialHostId,
  final String? initialProviderInstanceId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentProviderSettingsPane> createState() =>
      _AgentProviderSettingsPaneState();
}

class _AgentProviderSettingsPaneState
    extends ConsumerState<AgentProviderSettingsPane> {
  bool _hostResolved = false;
  String? _wantedHostId;
  String? _hostId;
  late String? _selectedId = widget.initialProviderInstanceId;

  /// The edits in progress and the host state they started from.
  AgentProviderInstanceDraft? _draft;
  AgentProviderInstanceDraft? _baseline;
  String? _baselineKey;
  bool _changedElsewhere = false;
  final Map<String, AgentProviderPendingSecret> _secrets =
      <String, AgentProviderPendingSecret>{};

  /// An instance from Add Provider that the host does not know yet.
  AgentProviderInstanceDraft? _unsavedNew;
  bool _saving = false;
  String? _error;
  String _modelQuery = '';
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // "Checked 2m ago" has to age while the pane is open; a minute is the
    // label's resolution.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _secrets.clear();
    super.dispose();
  }

  bool get _dirty {
    final draft = _draft;
    final baseline = _baseline;
    if (draft == null || baseline == null) {
      return false;
    }
    return draft.isNew ||
        _secrets.isNotEmpty ||
        draft.signature != baseline.signature;
  }

  @override
  Widget build(BuildContext context) {
    final hosts = ref.watch(agentProviderHostOptionsProvider);
    _resolveHost(hosts);
    final hostId = _hostId;
    final support = ref.watch(agentProviderSettingsSupportProvider).value;
    final catalogAsync = ref.watch(
      agentProviderCatalogControllerProvider(hostId),
    );
    final settingsAsync = support?.providerSettings == true
        ? ref.watch(agentProviderSettingsControllerProvider(hostId))
        : null;
    final preferences = support?.preferences == true
        ? ref.watch(agentChatPreferencesProvider(hostId)).value
        : null;
    final catalog = catalogAsync.value;
    final now = DateTime.now();
    final header = AgentProviderHostBar(
      hosts: hosts,
      selectedHostId: hostId,
      onSelect: (next) => unawaited(_selectHost(next)),
      checking: catalog?.checking ?? false,
      checkedLabel: agentProviderCheckedLabel(
        agentProviderOldestCheck(catalog?.rows ?? const []),
        now,
      ),
      onRefresh: catalog == null ? null : _refresh,
    );
    final Widget body;
    if (catalog == null || support == null) {
      body = catalogAsync.hasError
          ? AleraEmptyState(
              icon: AleraIcons.error,
              title: 'Providers unavailable',
              message: AgentProviderSettingsFailure.from(catalogAsync.error!)
                  .message,
              action: OutlinedButton(
                onPressed: () => ref.invalidate(
                  agentProviderCatalogControllerProvider(hostId),
                ),
                child: const Text('Try Again'),
              ),
            )
          : const AleraEmptyState(loading: true, message: 'Loading providers…');
    } else {
      body = _buildMasterDetail(
        catalog: catalog,
        snapshot: settingsAsync?.value,
        settingsError: settingsAsync?.error,
        support: support,
        preferences: preferences,
        now: now,
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_closeAfterLeaving());
        }
      },
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          header,
          if (catalog?.refreshError case final error?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AleraInlineNotice(message: error, tone: .error),
          ],
          if (settingsAsync?.value?.migrationError
              case final error?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AleraInlineNotice(
              message:
                  'The provider file from an older version could not be '
                  'imported and was left in place: $error',
              tone: .warning,
            ),
          ],
          const SizedBox(height: AleraTokens.space16),
          Expanded(child: body),
        ],
      ),
    );
  }

  void _resolveHost(List<AgentProviderHostOption> hosts) {
    if (!_hostResolved) {
      _hostResolved = true;
      _wantedHostId = normalizedRemoteHostId(
        widget.initialHostId ??
            ref.read(agentProviderActiveWorkspaceHostProvider),
      );
    }
    // Remote Hosts may still be loading on the first frame, so the wanted
    // host is applied once it is listed, unless the person already picked one.
    final wanted = _wantedHostId;
    if (wanted != null) {
      final resolved = agentProviderInitialHost(
        options: hosts,
        requestedHostId: wanted,
      );
      if (resolved != null) {
        _hostId = resolved;
        _wantedHostId = null;
      }
    }
    // A host removed from Remote Hosts while the pane is open falls back to
    // This Device rather than showing a host that no longer exists.
    if (!hosts.any((host) => host.hostId == _hostId)) {
      _hostId = null;
    }
  }

  Widget _buildMasterDetail({
    required AgentProviderCatalogState catalog,
    required AgentChatProviderSettingsSnapshot? snapshot,
    required Object? settingsError,
    required AgentProviderSettingsSupport support,
    required AgentChatPreferences? preferences,
    required DateTime now,
  }) {
    final entries = agentProviderEntries(
      catalog: catalog.rows,
      snapshot: snapshot,
      unsavedNew: _unsavedNew,
    );
    final selected =
        entries.where((entry) => entry.id == _selectedId).firstOrNull ??
        entries.firstOrNull;
    if (selected == null) {
      return const AleraEmptyState(
        icon: AleraIcons.agent,
        title: 'No providers',
        message: 'This host reports no Agent Chat providers.',
      );
    }
    _seed(
      selected,
      snapshotLoaded: snapshot != null || !support.providerSettings,
    );
    final draft = _draft!;
    final launchEditable =
        support.providerSettings && snapshot != null && !_saving;
    final defaultSelection = preferences?.defaultSelection;
    return AleraMasterDetail(
      masterTitle: 'Providers',
      masterAction: AleraIconButton(
        tooltip: 'Add Provider',
        icon: AleraIcons.add,
        onPressed: launchEditable
            ? () => unawaited(_addProvider(entries))
            : null,
      ),
      master: SingleChildScrollView(
        child: AleraPanel(
          clipBehavior: .antiAlias,
          children: <Widget>[
            for (final entry in entries)
              AgentProviderListRow(
                key: ValueKey<String>('provider-row-${entry.id}'),
                provider: entry.provider,
                label: entry.label,
                version: entry.catalog?.version,
                status: _statusOf(entry, catalog.checking),
                selected: entry.id == selected.id,
                enabled: entry.enabled,
                isDefault: defaultSelection?.providerInstanceId == entry.id,
                unsaved: entry.unsaved,
                onTap: () => unawaited(_selectRow(entry.id)),
                onEnabledChanged: launchEditable && !entry.unsaved
                    ? (value) => unawaited(_setEnabled(entry, value))
                    : null,
                enabledLockedReason: entry.unsaved
                    ? 'Save this provider before turning it on or off.'
                    : !support.providerSettings
                    ? 'Update the Alera runtime to turn providers on or off.'
                    : null,
              ),
          ],
        ),
      ),
      detail: _buildDetail(
        entry: selected,
        draft: draft,
        catalog: catalog,
        settingsError: settingsError,
        support: support,
        preferences: preferences,
        launchEditable: launchEditable,
        now: now,
      ),
    );
  }

  AgentProviderStatus _statusOf(AgentProviderEntry entry, bool checking) {
    final row = entry.catalog;
    if (row == null) {
      return AgentProviderStatus(
        kind: entry.enabled ? .unknownSignIn : .off,
        detail: entry.unsaved
            ? 'Save this provider to check it on this host.'
            : 'This host has not reported a status for it yet.',
      );
    }
    return agentProviderStatusOf(row, checking: checking);
  }

  Widget _buildDetail({
    required AgentProviderEntry entry,
    required AgentProviderInstanceDraft draft,
    required AgentProviderCatalogState catalog,
    required Object? settingsError,
    required AgentProviderSettingsSupport support,
    required AgentChatPreferences? preferences,
    required bool launchEditable,
    required DateTime now,
  }) {
    final defaultLabel = agentProviderDefaultLabel(entry.provider);
    final title = draft.label.trim().isEmpty
        ? defaultLabel
        : draft.label.trim();
    final local = _hostId == null;
    final canRunSetup = local || support.remoteSetup;
    final String? launchReadOnlyReason = !support.providerSettings
        ? 'The Alera runtime needs an update before provider launch settings '
              'can be edited here.'
        : settingsError != null
        ? AgentProviderSettingsFailure.from(settingsError).message
        : null;
    final prefsEditable = preferences != null && !_saving;
    return AgentProviderDetail(
      key: ValueKey<String>('provider-detail-${_hostId ?? ''}-${entry.id}'),
      title: title,
      defaultLabel: defaultLabel,
      status: _statusOf(entry, catalog.checking),
      now: now,
      catalog: entry.catalog,
      canRunSetup: canRunSetup,
      setupHostLabel: local ? null : _hostLabel(),
      // A runtime without remote setup cannot route the terminal to the
      // host, so the commands stay copy-only there.
      setupUnavailableReason: canRunSetup
          ? null
          : 'Setup commands run in a terminal on This Device only. Run them '
                'in a terminal on this host, then press Refresh.',
      onRunSetup: canRunSetup
          ? (command) => unawaited(_runSetup(entry.id, command, title))
          : null,
      editing: AgentProviderDraftEditing(
        draft: draft,
        pendingSecrets: Map<String, AgentProviderPendingSecret>.unmodifiableOf(
          _secrets,
        ),
        enabled: launchEditable,
        onChanged: _edit,
        onSetSecret: (name, value) => setState(() {
          _secrets[name] = AgentProviderPendingSecret(name: name, value: value);
          _error = null;
        }),
        onClearSecret: (name) => setState(() {
          _secrets[name] = AgentProviderPendingSecret(name: name);
          _error = null;
        }),
        onUndoSecret: (name) => setState(() => _secrets.remove(name)),
      ),
      defaults: _defaultsGroup(entry, draft, title, preferences, prefsEditable),
      models: _modelsGroup(
        entry,
        draft,
        preferences,
        prefsEditable,
        launchEditable,
      ),
      dirty: _dirty,
      saving: _saving,
      error: _error,
      problems: draft.validate(),
      launchReadOnlyReason: launchReadOnlyReason,
      changedElsewhereMessage: _changedElsewhere && _dirty
          ? 'This provider changed on another device after you started '
                'editing. Save replaces those changes; Revert loads them.'
          : null,
      removeLabel: entry.unsaved
          ? null
          : draft.isBuiltIn
          ? (draft.hasOverride ? 'Reset To Defaults' : null)
          : 'Remove Provider',
      onRemove: launchEditable && !entry.unsaved && draft.hasOverride
          ? () => unawaited(_remove(entry, title))
          : null,
      onSave: () => unawaited(_save()),
      onRevert: _revert,
    );
  }

  /// The selected host's name as Remote Hosts lists it.
  String _hostLabel() =>
      ref
          .read(agentProviderHostOptionsProvider)
          .where((host) => host.hostId == _hostId)
          .firstOrNull
          ?.label ??
      'This Device';

  /// Lets the part-file extensions rebuild without calling the protected
  /// [setState] from outside the class.
  void _update(VoidCallback change) => setState(change);

  void _edit(AgentProviderInstanceDraft next) {
    setState(() {
      _draft = next;
      _error = null;
    });
  }

  void _revert() {
    setState(() {
      _secrets.clear();
      _error = null;
      _changedElsewhere = false;
      if (_draft?.isNew ?? false) {
        _unsavedNew = null;
        _selectedId = null;
      }
      _baselineKey = null;
      _draft = null;
      _baseline = null;
    });
  }
}
