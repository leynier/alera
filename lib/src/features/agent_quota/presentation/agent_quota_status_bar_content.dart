import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_provider_icon.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';

import 'agent_quota_inline_actions.dart';

part 'agent_quota_status_bar_menus.dart';
part 'agent_quota_hover_card.dart';
part 'agent_quota_status_bar_readings.dart';
part 'agent_quota_overview_panel.dart';

typedef AgentQuotaPinToggle = void Function(String pinKey, bool pinned);

class AgentQuotaStatusBarContent extends StatelessWidget {
  const AgentQuotaStatusBarContent({
    super.key,
    required this.hostId,
    this.actions = const AgentQuotaInlineActions(),
    required this.snapshots,
    required this.settings,
    required this.onRefresh,
    required this.onTogglePinned,
    this.loading = false,
    this.error,
    this.trailing,
    this.onOpenUsage,
  });

  final String hostId;
  final AgentQuotaInlineActions actions;
  final List<AgentQuotaSnapshot> snapshots;
  final AgentQuotaHostSettings settings;
  final VoidCallback onRefresh;
  final AgentQuotaPinToggle onTogglePinned;
  final bool loading;
  final String? error;
  final Widget? trailing;
  final VoidCallback? onOpenUsage;

  @override
  Widget build(BuildContext context) {
    final enabled = _enabledSnapshots();
    final pinned = _pinnedSnapshots(enabled);
    return Container(
      height: AleraTokens.statusBarHeight,
      decoration: const BoxDecoration(
        color: AleraTokens.surface,
        border: Border(top: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return _CollapsedQuotaBar(
              hostId: hostId,
              actions: actions,
              snapshots: enabled,
              settings: settings,
              loading: loading,
              error: error,
              onRefresh: onRefresh,
              onTogglePinned: onTogglePinned,
              onOpenUsage: onOpenUsage,
              trailing: trailing,
            );
          }
          final compact = constraints.maxWidth < 1400;
          return Row(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      AleraIcons.host,
                      size: 13,
                      color: AleraTokens.foregroundFaint,
                    ),
                    const SizedBox(width: AleraTokens.space4),
                    Text(
                      hostId == 'local' ? 'Local' : hostId,
                      overflow: TextOverflow.ellipsis,
                      style: AleraTokens.monoStyle.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
              _QuotaOverviewButton(
                snapshots: enabled,
                settings: settings,
                hostId: hostId,
                actions: actions,
                error: error,
                onTogglePinned: onTogglePinned,
                onOpenUsage: onOpenUsage,
                profileLabelFor: _claudeProfileLabel,
              ),
              const VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final snapshot in pinned)
                        _QuotaProviderSummary(
                          snapshot: snapshot,
                          profileLabel: _claudeProfileLabel(snapshot),
                          compact: compact,
                          hostId: hostId,
                          actions: actions,
                        ),
                      if (enabled.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AleraTokens.space8,
                          ),
                          child: Text(
                            loading
                                ? 'Refreshing quotas'
                                : error == null
                                ? 'No quota data'
                                : 'Quota refresh failed',
                            style: AleraTokens.monoStyle.copyWith(fontSize: 10),
                          ),
                        ),
                      _QuotaRefreshButton(
                        loading: loading,
                        onRefresh: onRefresh,
                      ),
                    ],
                  ),
                ),
              ),
              trailing ?? const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }

  List<AgentQuotaSnapshot> _pinnedSnapshots(List<AgentQuotaSnapshot> enabled) {
    return <AgentQuotaSnapshot>[
      for (final snapshot in enabled)
        if (!settings.unpinnedQuotaKeys.contains(snapshot.pinKey)) snapshot,
    ];
  }

  List<AgentQuotaSnapshot> _enabledSnapshots() {
    final byProvider = <AgentQuotaProviderId, List<AgentQuotaSnapshot>>{};
    for (final snapshot in snapshots) {
      byProvider.putIfAbsent(snapshot.provider, () => []).add(snapshot);
    }
    final visible = <AgentQuotaSnapshot>[];
    for (final provider in settings.enabledProviders) {
      final candidates = byProvider[provider];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }
      if (provider == AgentQuotaProviderId.claude ||
          provider == AgentQuotaProviderId.opencode) {
        final byAccount = <String, AgentQuotaSnapshot>{
          for (final snapshot in candidates) snapshot.accountId: snapshot,
        };
        final addedAccounts = <String>{};
        if (provider == AgentQuotaProviderId.opencode ||
            settings.claudeDefaultEnabled) {
          final defaultSnapshot = byAccount['default'];
          if (defaultSnapshot != null) {
            visible.add(defaultSnapshot);
            addedAccounts.add('default');
          }
        } else {
          addedAccounts.add('default');
        }
        for (final profile in settings.claudeProfiles) {
          final snapshot = byAccount[profile.profile];
          if (snapshot != null) {
            visible.add(snapshot);
            addedAccounts.add(profile.profile);
          }
        }
        visible.addAll(
          candidates.where(
            (snapshot) => !addedAccounts.contains(snapshot.accountId),
          ),
        );
      } else {
        visible.add(candidates.first);
      }
    }
    return visible;
  }

  String? _claudeProfileLabel(AgentQuotaSnapshot snapshot) {
    if (snapshot.provider == AgentQuotaProviderId.opencode) {
      return snapshot.accountId == 'go' ? 'Go' : 'Zen';
    }
    if (snapshot.provider != AgentQuotaProviderId.claude) {
      return null;
    }
    if (snapshot.accountId == 'default') {
      return 'Default';
    }
    for (final profile in settings.claudeProfiles) {
      if (profile.profile == snapshot.accountId) {
        return profile.alias;
      }
    }
    return snapshot.displayName;
  }
}
